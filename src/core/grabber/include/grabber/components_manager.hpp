#pragma once

// `krbn::grabber::components_manager` can be used safely in a multi-threaded environment.

#include "components_manager_killer.hpp"
#include "console_user_server_client.hpp"
#include "constants.hpp"
#include "grabber/grabber_state_json_writer.hpp"
#include "hid_event_system_monitor.hpp"
#include "logger.hpp"
#include "monitor/version_monitor.hpp"
#include "receiver.hpp"
#include "session_monitor_receiver.hpp"
#include <pqrs/dispatcher.hpp>
#include <pqrs/osx/session.hpp>

namespace krbn {
namespace grabber {
class components_manager final : public pqrs::dispatcher::extra::dispatcher_client {
public:
  components_manager(const components_manager&) = delete;

  components_manager(std::weak_ptr<grabber_state_json_writer> weak_grabber_state_json_writer) : dispatcher_client(),
                                                                                                weak_grabber_state_json_writer_(weak_grabber_state_json_writer) {
    //
    // version_monitor_
    //

    version_monitor_ = std::make_unique<krbn::version_monitor>(krbn::constants::get_version_file_path());

    version_monitor_->changed.connect([](auto&& version) {
      if (auto killer = components_manager_killer::get_shared_components_manager_killer()) {
        killer->async_kill();
      }
    });

    //
    // session_monitor_receiver_
    //

    session_monitor_receiver_ = std::make_unique<session_monitor_receiver>();

    session_monitor_receiver_->current_console_user_id_changed.connect([this](auto&& uid) {
      uid_t console_user_server_socket_uid = 0;

      if (uid) {
        logger::get_logger()->info("current_console_user_id: {0}", *uid);
        console_user_server_socket_uid = *uid;
      } else {
        logger::get_logger()->info("current_console_user_id: none");
      }

      start_receiver(console_user_server_socket_uid);
    });

    //
    // hid_event_system_monitor_
    //

    hid_event_system_monitor_ = std::make_unique<hid_event_system_monitor>();
  }

  virtual ~components_manager(void) {
    detach_from_dispatcher([this] {
      receiver_ = nullptr;
      session_monitor_receiver_ = nullptr;
      version_monitor_ = nullptr;
    });
  }

  void async_start(void) {
    enqueue_to_dispatcher([this] {
      version_monitor_->async_start();

      start_receiver(0);

      session_monitor_receiver_->async_start();
    });
  }

private:
  void start_receiver(uid_t uid) {
    version_monitor_->async_manual_check();

    // receiver_

    receiver_ = nullptr;
    receiver_ = std::make_unique<receiver>(uid,
                                           weak_grabber_state_json_writer_);
  }

  std::weak_ptr<grabber_state_json_writer> weak_grabber_state_json_writer_;

  std::unique_ptr<version_monitor> version_monitor_;
  std::unique_ptr<session_monitor_receiver> session_monitor_receiver_;
  std::unique_ptr<hid_event_system_monitor> hid_event_system_monitor_;
  std::unique_ptr<receiver> receiver_;
};
} // namespace grabber
} // namespace krbn
