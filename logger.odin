package shooter

import "base:runtime"
import "core:log"

initialize_logger :: proc(target_context: ^runtime.Context) {
	target_context.logger = log.create_console_logger()
}

deinitialize_logger :: proc() {
	log.destroy_console_logger(context.logger)
}

log_info :: proc(args: ..any, loc := #caller_location) {
	log.info(..args, location = loc)
}

log_warning :: proc(args: ..any, loc := #caller_location) {
	log.warn(..args, location = loc)
}

log_error :: proc(args: ..any, loc := #caller_location) {
	log.error(..args, location = loc)
}
