package shooter

import "base:runtime"
import "core:log"

initialize_logger :: proc(target_context: ^runtime.Context) {
	target_context.logger = log.create_console_logger()
}

deinitialize_logger :: proc() {
	log.destroy_console_logger(context.logger)
}

log_info :: proc(fmt_str: string, args: ..any, loc := #caller_location) {
	log.infof(fmt_str, ..args, location = loc)
}

log_warning :: proc(fmt_str: string, args: ..any, loc := #caller_location) {
	log.warnf(fmt_str, ..args, location = loc)
}

log_error :: proc(fmt_str: string, args: ..any, loc := #caller_location) {
	log.errorf(fmt_str, ..args, location = loc)
}
