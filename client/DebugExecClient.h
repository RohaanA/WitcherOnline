#pragma once
#include "NetProto.h"
#include <atomic>
#include <optional>
#include <string>
#include <thread>
#include <vector>
#include <winsock2.h>
#include <windows.h>
#include <deque>
#include <unordered_map>

namespace w3mp {

	class DebugExecClient {
	public:
		DebugExecClient();
		~DebugExecClient();

		void Start();
		void Stop();
		bool IsConnected() const { return connected_.load(); }

		bool ExecTagged(const std::string& code, const std::string& prefixTag,
			std::string& out_text, int timeout_ms = 500);

		bool ExecNoWait(const std::string& code);

		bool ExecNoWaitLatest(const std::string& key, const std::string& code);

	private:
		SOCKET sock_ = INVALID_SOCKET;
		bool wsa_inited_ = false;
		std::atomic<bool> connected_{ false };

		bool SendAll(const uint8_t* p, size_t n);
		bool SendPacket(const std::vector<uint8_t>& pkt);
		bool SendBind();
		void CloseSocket();
		SOCKET Connect();

		std::thread worker_;
		std::atomic<bool> running_{ false };

		// Wine workaround: use Win32 native CRITICAL_SECTION/CONDITION_VARIABLE
		// instead of std::mutex/std::condition_variable (which crash under Proton).
		CRITICAL_SECTION req_cs_;
		CONDITION_VARIABLE req_cv_;
		bool has_req_ = false;
		std::string req_code_;
		std::string req_tag_;

		CONDITION_VARIABLE rep_cv_;
		std::optional<std::string> req_reply_;

		bool req_sent_ = false;

		void ThreadMain();
		void ThreadMainImpl();

		static void Utf8Sink(const std::string& s, void* user);
		void OnUtf8(const std::string& s);

		CRITICAL_SECTION ff_cs_;
		std::deque<std::string> ff_q_;

		std::unordered_map<std::string, std::string> ff_latest_;
	};

}
