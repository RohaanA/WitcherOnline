#include "pch.h"
#include "script.h"
#include <iostream>
#include "DebugExecClient.h"
#include <windows.h>
#include <thread>
#include <atomic>
#include <string>
#include <sstream>
#include <vector>
#include <regex>
#include <filesystem>
#include "pugixml\pugixml.hpp"
#include <unordered_set>
#define ASIO_STANDALONE
#include <asio.hpp>
namespace fs = std::filesystem;
using namespace w3mp;

static DebugExecClient g_client;
static std::thread g_poll;
static std::thread g_game;

std::string username = "Player";

static HANDLE g_initThread = NULL;

asio::io_context io;
asio::ip::udp::resolver resolver(io);
asio::ip::udp::socket theSocket(io);
asio::ip::udp::endpoint serverEndpoint;

static std::atomic<bool> g_usernameTaken{ false };
static std::atomic<bool> g_banned{ false };
static std::atomic<bool> g_notWhitelisted{ false };
static std::atomic<bool> g_kicked{ false };
static std::atomic<bool> g_shutdown{ false };
static std::atomic<bool> g_run{ false };

struct ExecJob {
	std::string code, tag;
	int timeoutMs;
};

static std::mutex g_qMu;
static std::vector<ExecJob> g_jobs;

static void LogStep(const char* msg);
static bool SendOneShotExec(const std::string& code);

fs::path getExecutablePath() {
	char buffer[MAX_PATH];
	GetModuleFileNameA(NULL, buffer, MAX_PATH);
	return fs::path(buffer).parent_path().parent_path();
}

struct ParsedHalves
{
	std::vector<std::string> first;
	std::vector<std::string> second;
};

static ParsedHalves ParseValuesSplitHalf(const std::string& input)
{
	static const std::string kStartMarker = "_s";
	static const std::string kEndMarker = "_e";
	static const std::string kHalfMarker = "half";

	std::istringstream iss(input);
	std::string word;

	ParsedHalves out;
	std::vector<std::string>* current = &out.first;

	if (!(iss >> word))
		return out;

	bool inBlock = false;
	std::string blockAccum;

	while (iss >> word)
	{
		if (!inBlock)
		{
			if (word == kStartMarker)
			{
				inBlock = true;
				blockAccum.clear();
				continue;
			}

			if (word == kHalfMarker)
			{
				current = &out.second;
				continue;
			}

			if (word == kEndMarker)
			{
				current->push_back(word);
				continue;
			}

			current->push_back(word);
		}
		else
		{
			if (word == kEndMarker)
			{
				current->push_back(blockAccum);
				inBlock = false;
				blockAccum.clear();
			}
			else
			{
				if (!blockAccum.empty())
					blockAccum += ' ';
				blockAccum += word;
			}
		}
	}

	if (inBlock && !blockAccum.empty())
	{
		current->push_back(blockAccum);
	}

	return out;
}

void PostExec(const std::string& code, const std::string& tag = "", int to = 300) {
	if (!g_run.load())
		return;

	std::lock_guard<std::mutex> lk(g_qMu);
	g_jobs.push_back({ code, tag, to });
}

static std::string EscapeField(const std::string& s)
{
	std::string out;
	out.reserve(s.size());

	for (char c : s)
	{
		if (c == '\\') out += "\\\\";
		else if (c == '\t') out += "\\t";
		else if (c == '\n') out += "\\n";
		else if (c == '\r') out += "\\r";
		else out += c;
	}

	return out;
}

static std::string BuildPacket(const std::string& opcode, const std::string& id, const std::vector<std::string>& fields)
{
	std::string packet = opcode + "\t" + id;

	for (const auto& f : fields)
	{
		packet += "\t";
		packet += EscapeField(f);
	}

	return packet;
}

static std::vector<std::string> SplitTabs(const std::string& s)
{
	std::vector<std::string> parts;
	std::string cur;
	bool esc = false;

	for (char c : s)
	{
		if (esc) {
			if (c == 't') cur += '\t';
			else if (c == 'n') cur += '\n';
			else if (c == 'r') cur += '\r';
			else if (c == '\\') cur += '\\';
			else cur += c;
			esc = false;
		}
		else if (c == '\\') {
			esc = true;
		}
		else if (c == '\t') {
			parts.push_back(cur);
			cur.clear();
		}
		else {
			cur += c;
		}
	}

	parts.push_back(cur);
	return parts;
}

static std::string EscapeExecQuoted(const std::string& s, char quote)
{
	std::string out;
	out.reserve(s.size() + 8);

	for (char c : s)
	{
		if (c == '\\')
			out += "\\\\";
		else if (c == quote)
		{
			out += '\\';
			out += c;
		}
		else if (c == '\n')
			out += "\\n";
		else if (c == '\r')
			out += "\\r";
		else if (c == '\t')
			out += "\\t";
		else
			out += c;
	}

	return out;
}

static void AppendExecField(std::string& code, const std::string& value)
{
	code += ", ";

	if (value.find_first_of(" \t\r\n") != std::string::npos)
	{
		code += "'";
		code += EscapeExecQuoted(value, '\'');
		code += "'";
	}
	else
	{
		code += value;
	}
}

void pushPlayer(const std::string& id, const std::vector<std::string>& update1A, const std::vector<std::string>& update1B,
	const std::vector<std::string>& update2A, const std::vector<std::string>& update2B)
{
	if (id.empty())
		return;

	std::vector<std::string> firstHalf;
	firstHalf.reserve(update1A.size() + update1B.size());
	firstHalf.insert(firstHalf.end(), update1A.begin(), update1A.end());
	firstHalf.insert(firstHalf.end(), update1B.begin(), update1B.end());

	std::vector<std::string> secondHalf;
	secondHalf.reserve(update2A.size() + update2B.size());
	secondHalf.insert(secondHalf.end(), update2A.begin(), update2A.end());
	secondHalf.insert(secondHalf.end(), update2B.begin(), update2B.end());

	if (firstHalf.empty() || secondHalf.empty())
		return;

	std::string code1 = "wo_update(";
	code1 += "\"";
	code1 += EscapeExecQuoted(id, '"');
	code1 += "\"";

	for (size_t i = 0; i < firstHalf.size(); ++i)
	{
		AppendExecField(code1, firstHalf[i]);
	}

	code1 += ")";

	std::string code2 = "wo_update2(";
	code2 += "\"";
	code2 += EscapeExecQuoted(id, '"');
	code2 += "\"";

	for (size_t i = 0; i < secondHalf.size(); ++i)
	{
		AppendExecField(code2, secondHalf[i]);
	}

	code2 += ")";

	// Deck-friendly: g_client may not be started; use one-shot TCP instead.
	SendOneShotExec(code1);
	SendOneShotExec(code2);

	//std::cout << "Code1: " << code1 << "\n";
	//std::cout << "Code2: " << code2 << "\n";
}

static void pushPlayer3(const std::string& id, const std::vector<std::string>& update3)
{
	if (id.empty() || update3.size() < 2)
		return;

	const std::string& outgoingGwentTo = update3[0];
	const std::string& outgoingGwentRequest = update3[1];
	const std::string& outgoingGwentBet = update3[2];
	const std::string& outgoingGwentSeed = update3[3];
	const std::string& lastGwentAction = update3[4];
	const std::string& lastGwentActionTime = update3[5];

	std::string gwentData;
	for (size_t i = 6; i < update3.size(); ++i)
	{
		if (!gwentData.empty())
			gwentData += " ";

		gwentData += update3[i];
	}

	std::string code3 = "wo_update3(";
	code3 += "\"";
	code3 += EscapeExecQuoted(id, '"');
	code3 += "\"";

	code3 += ", \"";
	code3 += EscapeExecQuoted(outgoingGwentTo, '"');
	code3 += "\"";

	code3 += ", ";
	code3 += outgoingGwentRequest;

	code3 += ", ";
	code3 += outgoingGwentBet;

	code3 += ", ";
	code3 += outgoingGwentSeed;

	code3 += ", \"";
	code3 += EscapeExecQuoted(lastGwentAction, '"');
	code3 += "\"";

	code3 += ", ";
	code3 += lastGwentActionTime;

	code3 += ", \"";
	code3 += EscapeExecQuoted(gwentData, '"');
	code3 += "\")";

	SendOneShotExec(code3);
}

static void CloseOnlineSession()
{
	try
	{
		if (theSocket.is_open())
			theSocket.close();
	}
	catch (...)
	{
	}
}

struct RemotePlayerChunks
{
	std::vector<std::string> update1A;
	std::vector<std::string> update1B;
	std::vector<std::string> update2A;
	std::vector<std::string> update2B;

	bool has1A = false;
	bool has1B = false;
	bool has2A = false;
	bool has2B = false;
};

std::mutex remoteMu;
std::unordered_map<std::string, RemotePlayerChunks> remotePlayers;

static void HandleServerPacket(const std::string& msg)
{
	auto parts = SplitTabs(msg);
	if (parts.empty())
		return;

	if (parts[0] == "ERROR")
	{
		if (parts.size() >= 2 && parts[1] == "USERNAME_TAKEN")
		{
			g_usernameTaken.store(true);
			CloseOnlineSession();
		}
		else if (parts.size() >= 2 && parts[1] == "BANNED")
		{
			g_banned.store(true);
			CloseOnlineSession();
		}
		else if (parts.size() >= 2 && parts[1] == "NOT_WHITELISTED")
		{
			g_notWhitelisted.store(true);
			CloseOnlineSession();
		}

		return;
	}
	else if (parts[0] == "KICK")
	{
		g_kicked.store(true);
		CloseOnlineSession();
		return;
	}
	else if (parts[0] == "UPDATE_NPC")
	{
		// parts[1] = host username, parts[2] = serialized NPC payload (single field).
		// We inject wo_npc_update(host, payload) into the game.
		// Coalescing key: "npc:<host>" — drop stale updates if newer arrives first.
		if (parts.size() < 3)
			return;

		const std::string& hostId = parts[1];
		const std::string& payload = parts[2];

		if (hostId.empty() || payload.empty())
			return;

		// Self-echo filter: don't render our own NPCs as remotes (would double them).
		if (hostId == username)
			return;

		std::string code = "wo_npc_update(\"";
		code += EscapeExecQuoted(hostId, '"');
		code += "\", \"";
		code += EscapeExecQuoted(payload, '"');
		code += "\")";

		// Deck-friendly: one-shot TCP push instead of background queue.
		SendOneShotExec(code);
		return;
	}
	else if (parts[0] == "UPDATE_HIT")
	{
		// parts[1] = attacker username, parts[2] = payload "<host> <npcId> <damage>|<host> ..."
		// Host applies damage to NPC by ID. Attacker is informational (could be used for kill credit).
		if (parts.size() < 3)
			return;

		const std::string& attackerId = parts[1];
		const std::string& payload = parts[2];

		if (payload.empty())
			return;

		std::string code = "wo_apply_hit(\"";
		code += EscapeExecQuoted(attackerId, '"');
		code += "\", \"";
		code += EscapeExecQuoted(payload, '"');
		code += "\")";

		// Deck-friendly: one-shot TCP push (also handles hits)
		SendOneShotExec(code);
		return;
	}
	else if (parts[0] == "UPDATE_EXEC")
	{
		// Verbatim exec relay: parts[2] = '|'-separated exec strings to inject as-is.
		// The engine binds quoted tokens to typed params (e.g. wo_give_item('X',1) -> name),
		// which is how we move items cross-process without WS string->name.
		if (parts.size() < 3)
			return;

		const std::string& sender = parts[1];
		const std::string& payload = parts[2];
		if (payload.empty())
			return;
		if (sender == username)   // self-echo: don't run our own queued action
			return;

		size_t start = 0;
		while (start <= payload.size())
		{
			size_t bar = payload.find('|', start);
			std::string code = (bar == std::string::npos)
				? payload.substr(start)
				: payload.substr(start, bar - start);

			// Guard: only inject our own wo_* helpers, never arbitrary remote code.
			if (code.rfind("wo_", 0) == 0)
				SendOneShotExec(code);

			if (bar == std::string::npos)
				break;
			start = bar + 1;
		}
		return;
	}
	else if (
		parts[0] == "UPDATE1A" ||
		parts[0] == "UPDATE1B" ||
		parts[0] == "UPDATE2A" ||
		parts[0] == "UPDATE2B" ||
		parts[0] == "UPDATE3")
	{
		if (parts.size() < 2)
			return;

		std::string opcode = parts[0];
		std::string id = parts[1];
		std::vector<std::string> fields(parts.begin() + 2, parts.end());

		if (opcode == "UPDATE3")
		{
			pushPlayer3(id, fields);
			return;
		}

		bool readyToPush = false;

		std::vector<std::string> u1a;
		std::vector<std::string> u1b;
		std::vector<std::string> u2a;
		std::vector<std::string> u2b;

		{
			// Deck workaround: std::mutex/lock_guard crashes under Wine.
			// HandleServerPacket is called only from SendToGameThread (single-threaded),
			// so we can safely skip the lock.
			auto& rp = remotePlayers[id];

			if (opcode == "UPDATE1A")
			{
				rp.update1A = std::move(fields);
				rp.has1A = true;
			}
			else if (opcode == "UPDATE1B")
			{
				rp.update1B = std::move(fields);
				rp.has1B = true;
			}
			else if (opcode == "UPDATE2A")
			{
				rp.update2A = std::move(fields);
				rp.has2A = true;
			}
			else if (opcode == "UPDATE2B")
			{
				rp.update2B = std::move(fields);
				rp.has2B = true;
			}

			if (rp.has1A && rp.has1B && rp.has2A && rp.has2B)
			{
				u1a = rp.update1A;
				u1b = rp.update1B;
				u2a = rp.update2A;
				u2b = rp.update2B;

				rp.has1A = false;
				rp.has1B = false;
				rp.has2A = false;
				rp.has2B = false;

				readyToPush = true;
			}
		}

		if (readyToPush)
		{
			pushPlayer(id, u1a, u1b, u2a, u2b);
		}

		return;
	}
}

// One-shot TCP push for Wine/Deck: open, bind, exec, close.
// No threading, no mutex, no condition variables. Synchronous.
static bool SendOneShotExec(const std::string& code)
{
	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (s == INVALID_SOCKET) return false;

	BOOL one = TRUE;
	setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char*)&one, sizeof(one));
	int to = 500;
	setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&to, sizeof(to));
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&to, sizeof(to));

	sockaddr_in addr{};
	addr.sin_family = AF_INET;
	addr.sin_port = htons(37001);
	if (InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr) != 1)
	{
		closesocket(s);
		return false;
	}

	if (connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR)
	{
		closesocket(s);
		return false;
	}

	// Send bind packets followed by exec, in single burst.
	auto b1 = w3mp::Bind("Remote");
	auto b2 = w3mp::Bind("scripts");
	auto pkt = w3mp::ExecutePacket(code);

	std::vector<uint8_t> burst;
	burst.insert(burst.end(), b1.begin(), b1.end());
	burst.insert(burst.end(), b2.begin(), b2.end());
	burst.insert(burst.end(), pkt.begin(), pkt.end());

	const uint8_t* p = burst.data();
	int n = (int)burst.size();
	while (n > 0)
	{
		int r = send(s, (const char*)p, n, 0);
		if (r <= 0) { closesocket(s); return false; }
		p += r; n -= r;
	}

	closesocket(s);
	return true;
}

static void PollPoseThread() {
	LogStep("PollPoseThread: ENTER");
	Sleep(500);
	LogStep("PollPoseThread: after sleep, entering main loop");
	using clock = std::chrono::steady_clock;
	auto lastDebugLog = clock::now();
	int iterLog = 0;

	while (g_run.load()) {
		if (iterLog < 5) { LogStep("PPT: A. loop top"); }
		// File log every 3 sec to see if poll runs and g_client status
		auto now = clock::now();
		if (now - lastDebugLog > std::chrono::seconds(3)) {
			std::string s = "PollPoseTick: g_client.IsConnected=";
			s += g_client.IsConnected() ? "TRUE" : "FALSE";
			LogStep(s.c_str());
			lastDebugLog = now;
		}
		if (iterLog < 5) { LogStep("PPT: B. after time check"); }
		if (iterLog < 5) { LogStep("PPT: B1. about to try block"); }


		try
		{
			if (iterLog < 5) { LogStep("PPT: B2. in try"); }
			// DECK: skip mutex+drain (suspect mutex on Wine)
			if (iterLog < 5) { LogStep("PPT: B5. after drain block (skipped)"); }

			if (g_client.IsConnected() && g_usernameTaken.load())
			{
				PostExec("usernameTaken(\"" + username + "\")", "", 150);
				Sleep(250);
				continue;
			}
			else if (g_client.IsConnected() && g_kicked.load())
			{
				PostExec("kickedMsg()", "", 150);
				Sleep(250);
				continue;
			}
			else if (g_client.IsConnected() && g_banned.load())
			{
				PostExec("bannedMsg()", "", 150);
				Sleep(250);
				continue;
			}
			else if (g_client.IsConnected() && g_notWhitelisted.load())
			{
				PostExec("notWhitelistedMsg()", "", 150);
				Sleep(250);
				continue;
			}

			if (iterLog < 5) { LogStep("PPT: B6. before main connected check"); }

			// Deck heartbeat: when no debug-scripts connection (Wine workaround mode),
			// still send a minimal UPDATE1A to keep server registration alive.
			static auto lastHeartbeat = clock::now();
			if (!g_client.IsConnected() && (now - lastHeartbeat) > std::chrono::seconds(2))
			{
				lastHeartbeat = now;
				try {
					std::string packet = "UPDATE1A\t" + username + "\theartbeat";
					theSocket.send(asio::buffer(packet));
				} catch (...) {}
			}

			if (g_client.IsConnected()) {

				// Per-cycle counter to throttle rarely-changing data (appearance).
				static uint32_t cycle = 0;
				++cycle;

				// Timeout for exec round-trips. Lower than the old 3000ms to cap worst-case
				// hitch when a reply is dropped, while staying generous enough for Wine's
				// batched debug-script replies.
				const int kTimeout = 1500;

				// Helper: exec a "halves"-style getter and send two UPDATE packets.
				// Returns false only on a failed round-trip (caller may ignore).
				auto pushHalves = [&](const char* fn, const char* tag,
				                      const char* opA, const char* opB) -> bool {
					std::string out;
					std::string code = std::string(fn) + "(\"" + username + "\")";
					if (!g_client.ExecTagged(code, tag, out, kTimeout))
						return false;
					ParsedHalves h = ParseValuesSplitHalf(out);
					try {
						if (!h.first.empty())
							theSocket.send(asio::buffer(BuildPacket(opA, username, h.first)));
						if (!h.second.empty())
							theSocket.send(asio::buffer(BuildPacket(opB, username, h.second)));
					} catch (...) {}
					return true;
				};

				// Helper: exec a single-string-payload getter (NPC / hits), strip the
				// "<tag> " prefix, send one packet. Empty payload => nothing sent.
				auto pushPayload = [&](const char* fn, const char* tag,
				                       const char* opcode) {
					std::string out;
					std::string code = std::string(fn) + "(\"" + username + "\")";
					if (!g_client.ExecTagged(code, tag, out, kTimeout))
						return;
					std::string prefix = std::string(tag) + " ";
					if (out.size() >= prefix.size() && out.compare(0, prefix.size(), prefix) == 0)
						out.erase(0, prefix.size());
					else if (out == tag)        // bare tag marker => empty
						out.clear();
					if (out.empty())
						return;
					std::vector<std::string> fields;
					fields.push_back(out);
					try {
						theSocket.send(asio::buffer(BuildPacket(opcode, username, fields)));
					} catch (...) {}
				};

				// --- Every cycle: position/state (latency-critical) ---
				pushHalves("wo_get", "wo", "UPDATE1A", "UPDATE1B");

				// --- Throttled: appearance changes rarely (armor swap). Every 30 cycles. ---
				if (cycle % 30 == 0)
					pushHalves("wo_get2", "wo2", "UPDATE2A", "UPDATE2B");

				// --- wo_get3 (gwent) removed: gwent multiplayer disabled on both sides. ---

				// --- Every cycle: NPC sync + hit queue ---
				pushPayload("wo_get_npcs", "wo_npc", "UPDATE_NPC");
				pushPayload("wo_get_pending_hits", "wo_hit", "UPDATE_HIT");

				// --- Throttled: verbatim exec relay (item give / drops). Rare -> every 8 cycles. ---
				if (cycle % 8 == 0)
					pushPayload("wo_get_pending_exec", "wo_exec", "UPDATE_EXEC");
			}
			else
			{
				if (iterLog < 5) { LogStep("PPT: C. about to sleep 100"); }
				Sleep(100);
				if (iterLog < 5) { LogStep("PPT: D. after sleep 100"); iterLog++; }
			}
		}
		catch (const std::exception& e)
		{
			std::string s = "PPT: caught std::exception: ";
			s += e.what();
			LogStep(s.c_str());
		}
		catch (...)
		{
			LogStep("PPT: caught unknown exception");
		}
	}
}

static void SendToGameThread()
{
	LogStep("SendToGameThread: ENTER");
	Sleep(1000);
	LogStep("SendToGameThread: after sleep, entering recv loop");
	std::vector<char> data(8192);

	int tick = 0;
	while (g_run.load())
	{
		try
		{
			if (tick < 3) { LogStep("SendToGameThread: about to recv_from"); }
			asio::ip::udp::endpoint senderEndpoint;

			std::size_t len = theSocket.receive_from(
				asio::buffer(data),
				senderEndpoint
			);
			if (tick < 3) { LogStep("SendToGameThread: recv_from returned"); }

			std::string msg(data.data(), len);
			HandleServerPacket(msg);
		}
		catch (const std::exception& e) {
			std::string s = "SendToGameThread recv exception: ";
			s += e.what();
			LogStep(s.c_str());
			Sleep(500);
		}
		catch (...) {
			LogStep("SendToGameThread unknown exception");
			Sleep(500);
		}
		tick++;
	}
}

// Wine-friendly file logger.
static void LogStep(const char* msg)
{
	FILE* f = nullptr;
	fopen_s(&f, "C:\\witcher_dll_log.txt", "a");
	if (f)
	{
		fprintf(f, "%s\n", msg);
		fclose(f);
	}
}

void initScript()
{
	LogStep("S0: enter initScript");

	// Skip when not running inside the main game exe (launcher.exe etc load dinput8 too).
	{
		char procPath[MAX_PATH] = {0};
		GetModuleFileNameA(NULL, procPath, MAX_PATH);
		std::string p(procPath);
		for (auto& c : p) c = (char)tolower((unsigned char)c);
		LogStep((std::string("S0a: proc = ") + p).c_str());
		if (p.find("witcher3.exe") == std::string::npos)
		{
			LogStep("S0a: not witcher3.exe, abort init");
			return;
		}
	}

	// Disable std::cout/cerr globally -- without an allocated console (which we no longer
	// activate to avoid Wine crashes), cout writes may crash on Wine/Proton.
	std::cout.rdbuf(nullptr);
	std::cerr.rdbuf(nullptr);
	std::clog.rdbuf(nullptr);
	LogStep("S0b: cout disabled");

	fs::path baseDir = getExecutablePath();
	LogStep("S1: got executable path");

	fs::path fullPath = baseDir / "WitcherOnline" / "config.xml";
	{
		std::string s = "S2: config path = ";
		s += fullPath.string();
		LogStep(s.c_str());
	}

	pugi::xml_document doc;
	pugi::xml_parse_result result = doc.load_file(fullPath.c_str());
	LogStep(result ? "S3: config loaded OK" : "S3: config load FAILED");
	if (!result) return;

	pugi::xml_node xml = doc.child("Config");
	if (!xml) { LogStep("S4: no <Config> root"); return; }
	LogStep("S4: <Config> root OK");

	std::string user = xml.child("Username").text().as_string();
	username = std::regex_replace(user, std::regex("[^A-Za-z0-9_]"), "");
	if (username.length() > 16) username.resize(16);

	std::string ip = xml.child("ServerIP").text().as_string();
	std::string port = xml.child("Port").text().as_string();
	{
		std::string s = "S5: user=" + username + " ip=" + ip + " port=" + port;
		LogStep(s.c_str());
	}

	if (ip.empty() || username.empty() || username.length() < 2) { LogStep("S5b: bad config, return"); return; }

	if (g_shutdown.load()) { LogStep("S5c: shutdown, return"); return; }

	LogStep("S6: g_client.Start() (Wine-safe: CRITICAL_SECTION/CONDITION_VARIABLE)");
	g_client.Start();
	LogStep("S7: g_client.Start() returned");

	g_run.store(true);
	LogStep("S8: g_run set");

	theSocket.open(asio::ip::udp::v4());
	LogStep("S9: socket open");

	theSocket.bind(asio::ip::udp::endpoint(asio::ip::udp::v4(), 0));
	LogStep("S10: socket bind");

	serverEndpoint = *resolver.resolve(asio::ip::udp::v4(), ip, port).begin();
	LogStep("S11: resolved server");

	theSocket.connect(serverEndpoint);
	LogStep("S12: socket connect");

	g_poll = std::thread(PollPoseThread);
	LogStep("S13: poll thread spawned");

	g_game = std::thread(SendToGameThread);
	LogStep("S14: game thread spawned, init complete");
}

static DWORD WINAPI InitThreadProc(LPVOID)
{
	if (g_shutdown.load())
		return 0;

	// activateConsole();  // disabled (crashes on Wine)
	initScript();
	return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID) {
	switch (reason) {
	case DLL_PROCESS_ATTACH:
		DisableThreadLibraryCalls(hModule);
		g_initThread = CreateThread(nullptr, 0, InitThreadProc, nullptr, 0, nullptr);
		if (g_initThread) {
			CloseHandle(g_initThread);
			g_initThread = NULL;
		}
		break;
	case DLL_PROCESS_DETACH:
	{
		g_shutdown.store(true);
		g_run.store(false);
		theSocket.close();
		g_client.Stop();

		{
			std::lock_guard<std::mutex> lk(g_qMu);
			g_jobs.clear();
		}

		if (g_poll.joinable())
			g_poll.join();

		if (g_game.joinable())
			g_game.join();

		//FreeConsole();
		break;
	}
	}
	return TRUE;
}