#include "DebugExecClient.h"
#include <ws2tcpip.h>
#include <windows.h>
#include <iostream>

#pragma comment(lib, "Ws2_32.lib")

namespace w3mp {

	static void DBG(const char* msg) {
		OutputDebugStringA(msg);
		std::cout << msg << std::endl;
	}

	DebugExecClient::DebugExecClient() {
		InitializeCriticalSection(&req_cs_);
		InitializeCriticalSection(&ff_cs_);
		InitializeConditionVariable(&req_cv_);
		InitializeConditionVariable(&rep_cv_);
	}

	DebugExecClient::~DebugExecClient() {
		Stop();
		DeleteCriticalSection(&req_cs_);
		DeleteCriticalSection(&ff_cs_);
	}

	static void StartLog(const char* s) {
		FILE* f = nullptr;
		fopen_s(&f, "C:\\witcher_dll_log.txt", "a");
		if (f) { fprintf(f, "DEC: %s\n", s); fclose(f); }
	}

	void DebugExecClient::Start() {
		StartLog("Start enter");
		if (running_.exchange(true)) { StartLog("Start: already running, return"); return; }
		StartLog("Start: running flag set");

		if (!wsa_inited_) {
			StartLog("Start: about to WSAStartup");
			WSADATA wsa{};
			int wr = WSAStartup(MAKEWORD(2, 2), &wsa);
			if (wr == 0) wsa_inited_ = true;
			StartLog(wsa_inited_ ? "Start: WSAStartup OK" : "Start: WSAStartup failed");
		}
		else { StartLog("Start: wsa already inited"); }

		StartLog("Start: about to spawn worker thread");
		worker_ = std::thread(&DebugExecClient::ThreadMain, this);
		StartLog("Start: worker thread spawned, returning");
	}

	void DebugExecClient::Stop() {
		if (!running_.exchange(false))
			return;

		EnterCriticalSection(&req_cs_);
		has_req_ = false;
		req_sent_ = false;
		req_reply_.reset();
		LeaveCriticalSection(&req_cs_);

		EnterCriticalSection(&ff_cs_);
		ff_q_.clear();
		ff_latest_.clear();
		LeaveCriticalSection(&ff_cs_);

		WakeAllConditionVariable(&req_cv_);
		WakeAllConditionVariable(&rep_cv_);

		if (worker_.joinable())
			worker_.join();

		CloseSocket();

		if (wsa_inited_) {
			WSACleanup();
			wsa_inited_ = false;
		}
	}


	bool DebugExecClient::ExecTagged(const std::string& code,
		const std::string& prefixTag,
		std::string& out_text,
		int timeout_ms)
	{
		if (!running_.load() || !connected_.load())
			return false;

		EnterCriticalSection(&req_cs_);
		req_code_ = code;
		req_tag_ = prefixTag;
		req_reply_.reset();
		has_req_ = true;
		req_sent_ = false;
		LeaveCriticalSection(&req_cs_);

		WakeConditionVariable(&req_cv_);

		auto deadline = std::chrono::steady_clock::now() +
			std::chrono::milliseconds(timeout_ms);

		EnterCriticalSection(&req_cs_);
		while (!req_reply_.has_value()) {
			if (!running_.load() || !connected_.load()) {
				has_req_ = false;
				req_sent_ = false;
				break;
			}

			auto remaining_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
				deadline - std::chrono::steady_clock::now()).count();
			if (remaining_ms <= 0) {
				has_req_ = false;
				req_sent_ = false;
				break;
			}

			BOOL ok = SleepConditionVariableCS(&rep_cv_, &req_cs_, (DWORD)remaining_ms);
			if (!ok && GetLastError() == ERROR_TIMEOUT) {
				has_req_ = false;
				req_sent_ = false;
				break;
			}
		}

		bool have_reply = req_reply_.has_value();
		if (have_reply) out_text = *req_reply_;
		LeaveCriticalSection(&req_cs_);
		return have_reply;
	}

	bool DebugExecClient::ExecNoWait(const std::string& code)
	{
		if (!running_.load() || !connected_.load())
			return false;

		EnterCriticalSection(&ff_cs_);
		ff_q_.push_back(code);
		LeaveCriticalSection(&ff_cs_);
		WakeConditionVariable(&req_cv_);
		return true;
	}

	bool DebugExecClient::ExecNoWaitLatest(const std::string& key, const std::string& code)
	{
		if (!running_.load() || !connected_.load())
			return false;

		EnterCriticalSection(&ff_cs_);
		ff_latest_[key] = code;
		LeaveCriticalSection(&ff_cs_);
		WakeConditionVariable(&req_cv_);
		return true;
	}

	void DebugExecClient::CloseSocket() {
		if (sock_ != INVALID_SOCKET) { closesocket(sock_); sock_ = INVALID_SOCKET; }
		connected_.store(false);
	}

	SOCKET DebugExecClient::Connect() {
		SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
		if (s == INVALID_SOCKET) return INVALID_SOCKET;

		BOOL one = TRUE; setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char*)&one, sizeof(one));
		int to = 50; setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&to, sizeof(to));
		setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&to, sizeof(to));

		sockaddr_in a{};
		a.sin_family = AF_INET;
		a.sin_port = htons(37001);

		// Always use ASCII version -- InetPtonW unreliable on Wine/Proton.
		if (InetPtonA(AF_INET, "127.0.0.1", &a.sin_addr) != 1) {
			closesocket(s);
			return INVALID_SOCKET;
		}

		if (connect(s, reinterpret_cast<sockaddr*>(&a), sizeof(a)) == SOCKET_ERROR) {
			closesocket(s);
			return INVALID_SOCKET;
		}
		return s;
	}

	bool DebugExecClient::SendAll(const uint8_t* p, size_t n) {
		while (n) {
			int r = send(sock_, (const char*)p, (int)n, 0);
			if (r <= 0) return false;
			p += r; n -= r;
	}
		return true;
}

	bool DebugExecClient::SendPacket(const std::vector<uint8_t>& pkt) {
		return SendAll(pkt.data(), pkt.size());
	}

	bool DebugExecClient::SendBind() {
		auto b1 = Bind("Remote");
		auto b2 = Bind("scripts");
		std::vector<uint8_t> burst;
		burst.insert(burst.end(), b1.begin(), b1.end());
		burst.insert(burst.end(), b2.begin(), b2.end());
		return SendPacket(burst);
	}

	void DebugExecClient::Utf8Sink(const std::string& s, void* user) {
		static_cast<DebugExecClient*>(user)->OnUtf8(s);
	}

	void DebugExecClient::OnUtf8(const std::string& raw) {
		std::string s = raw;
		while (!s.empty() && (s.back() == '\r' || s.back() == '\n' || s.back() == '\0')) {
			s.pop_back();
		}

		// DEBUG: dump first 120 chars of every received string
		{
			std::string preview = s.substr(0, 120);
			std::cout << "[DBG_RX " << s.size() << "B]: " << preview << "\n";
		}

		bool matched = false;
		EnterCriticalSection(&req_cs_);
		if (has_req_) {
			if (req_tag_.empty() || s.rfind(req_tag_, 0) == 0) {
				req_reply_ = s;
				has_req_ = false;
				req_sent_ = false;
				matched = true;
			}
		}
		LeaveCriticalSection(&req_cs_);
		if (matched) {
			WakeAllConditionVariable(&rep_cv_);
		}
	}

	void DebugExecClient::ThreadMain() {
		// Wine/Deck workaround: give the game time to fully load + bind debug-scripts port
		// before we hammer it with TCP connects.
		for (int i = 0; i < 50 && running_.load(); ++i) Sleep(100);  // ~5 sec total
		// Wrap entire thread to prevent process termination if anything throws.
		try {
			ThreadMainImpl();
		} catch (const std::exception& e) {
			DBG("[W3MP] ThreadMain exception, exiting thread\n");
			OutputDebugStringA("[W3MP] ThreadMain std::exception: ");
			OutputDebugStringA(e.what());
			OutputDebugStringA("\n");
		} catch (...) {
			DBG("[W3MP] ThreadMain unknown exception, exiting thread\n");
		}
		connected_.store(false);
	}

	void DebugExecClient::ThreadMainImpl() {
		std::vector<uint8_t> rx;

		auto send_exec = [&](const std::string& code) -> bool {
			auto pkt = ExecutePacket(code);
			if (!SendPacket(pkt)) {
				DBG("[W3MP] send failed, dropping\n");
				CloseSocket();
				return false;
			}
			return true;
			};

		while (running_.load()) {
			while (running_.load()) {
				sock_ = Connect();
				if (sock_ != INVALID_SOCKET) {
					DBG("[W3MP] Connected\n");
					if (SendBind()) {
						connected_.store(true);
						break;
					}
					DBG("[W3MP] Bind failed\n");
					CloseSocket();
				}
				for (int ms = 0; ms < 1000 && running_.load(); ms += 100)
					Sleep(100);
			}
			if (!running_.load())
				break;

			while (running_.load() && connected_.load()) {

				bool waiting_for_reply = false;
				bool have_tag = false;
				std::string tag_code;

				EnterCriticalSection(&req_cs_);
				waiting_for_reply = (has_req_ && req_sent_);
				if (!waiting_for_reply) {
					if (has_req_ && !req_sent_) {
						have_tag = true;
						tag_code = req_code_;
						req_sent_ = true;
					}
					else {
						SleepConditionVariableCS(&req_cv_, &req_cs_, 1);
					}
				}
				LeaveCriticalSection(&req_cs_);

				if (have_tag) {
					if (!send_exec(tag_code))
						break;
				}
				else if (!waiting_for_reply) {
					std::unordered_map<std::string, std::string> latest;
					EnterCriticalSection(&ff_cs_);
					latest.swap(ff_latest_);
					LeaveCriticalSection(&ff_cs_);

					for (auto& kv : latest) {
						if (!send_exec(kv.second)) {
							break;
						}
					}
					if (!connected_.load())
						break;

					std::string ff;
					EnterCriticalSection(&ff_cs_);
					if (!ff_q_.empty()) {
						ff = std::move(ff_q_.front());
						ff_q_.pop_front();
					}
					LeaveCriticalSection(&ff_cs_);
					if (!ff.empty()) {
						if (!send_exec(ff))
							break;
					}
				}

				uint8_t tmp[32768];
				int n = recv(sock_, (char*)tmp, sizeof(tmp), 0);

				if (n > 0) {
					rx.insert(rx.end(), tmp, tmp + n);
					size_t used = DecodeVisitUtf8Consume(rx, &DebugExecClient::Utf8Sink, this);
					if (used > 0) rx.erase(rx.begin(), rx.begin() + used);
					if (rx.size() > (1 << 20)) rx.clear();
				}
				else if (n == 0) {
					DBG("[W3MP] server closed\n");
					CloseSocket();
					break;
				}
				else {
					int e = WSAGetLastError();
					if (e != WSAETIMEDOUT && e != WSAEWOULDBLOCK) {
						char buf[128];
						sprintf_s(buf, "[W3MP] recv failed: %d\n", e);
						DBG(buf);
						CloseSocket();
						break;
					}
				}
			}
		}

		CloseSocket();
	}

}