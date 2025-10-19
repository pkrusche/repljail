pkgname <- "replr"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('replr')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("RREPLSession")
### * RREPLSession

flush(stderr()); flush(stdout())

### Name: RREPLSession
### Title: RREPLSession: R6 Class for Isolated R Session Management
### Aliases: RREPLSession

### ** Examples

## Not run: 
##D # Create a new session
##D session <- RREPLSession$new()
##D 
##D # Execute some R code
##D result <- session$execute("1 + 1")
##D print(result$result$output)
##D 
##D # Check if worker is alive
##D session$is_alive()
##D 
##D # Stop the session (optional - happens automatically on cleanup)
##D session$stop()
## End(Not run)




cleanEx()
nameEx("replr_check_syntax")
### * replr_check_syntax

flush(stderr()); flush(stdout())

### Name: replr_check_syntax
### Title: Check R Code Syntax
### Aliases: replr_check_syntax

### ** Examples

## Not run: 
##D # Check valid code
##D result <- replr_check_syntax("x <- 1 + 2\nprint(x)")
##D if (result$success) {
##D   cat("Valid syntax with", result$data$expression_count, "expressions\n")
##D }
##D 
##D # Check invalid code
##D result <- replr_check_syntax("x <- mean(c(1, 2, 3)")
##D if (!result$success) {
##D   cat("Syntax error:", result$error, "\n")
##D }
## End(Not run)



cleanEx()
nameEx("replr_check_syntax_tool")
### * replr_check_syntax_tool

flush(stderr()); flush(stdout())

### Name: replr_check_syntax_tool
### Title: Check R Code Syntax Tool Definition
### Aliases: replr_check_syntax_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D syntax_tool <- replr_check_syntax_tool()
##D print(syntax_tool$name)
##D print(syntax_tool$description)
## End(Not run)



cleanEx()
nameEx("replr_cleanup_sessions")
### * replr_cleanup_sessions

flush(stderr()); flush(stdout())

### Name: replr_cleanup_sessions
### Title: Clean Up Dead REPL Sessions
### Aliases: replr_cleanup_sessions

### ** Examples

## Not run: 
##D # Clean up any dead sessions
##D result <- replr_cleanup_sessions()
##D cat("Cleaned up", result$data$cleaned_count, "dead sessions")
## End(Not run)



cleanEx()
nameEx("replr_cleanup_sessions_tool")
### * replr_cleanup_sessions_tool

flush(stderr()); flush(stdout())

### Name: replr_cleanup_sessions_tool
### Title: Cleanup Sessions Tool Definition
### Aliases: replr_cleanup_sessions_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D cleanup_tool <- replr_cleanup_sessions_tool()
##D print(cleanup_tool$name)
## End(Not run)



cleanEx()
nameEx("replr_create_repl_session")
### * replr_create_repl_session

flush(stderr()); flush(stdout())

### Name: replr_create_repl_session
### Title: Create a New REPL Session for replr
### Aliases: replr_create_repl_session

### ** Examples

## Not run: 
##D # Create a new session with auto-generated ID
##D result <- replr_create_repl_session()
##D if (result$success) {
##D   session_id <- result$data$session_id
##D   cat("Created session:", session_id)
##D }
## End(Not run)



cleanEx()
nameEx("replr_create_repl_session_tool")
### * replr_create_repl_session_tool

flush(stderr()); flush(stdout())

### Name: replr_create_repl_session_tool
### Title: Create REPL Session Tool Definition
### Aliases: replr_create_repl_session_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D create_tool <- replr_create_repl_session_tool()
##D print(create_tool$name)
##D print(create_tool$description)
## End(Not run)



cleanEx()
nameEx("replr_execute_code")
### * replr_execute_code

flush(stderr()); flush(stdout())

### Name: replr_execute_code
### Title: Execute R Code in a REPL Session
### Aliases: replr_execute_code

### ** Examples

## Not run: 
##D # Create a session and execute code
##D session_result <- replr_create_repl_session()
##D session_id <- session_result$data$session_id
##D 
##D # Execute simple arithmetic
##D result <- replr_execute_code(session_id, "2 + 2")
##D if (result$success) {
##D   cat("Output:", result$data$output)
##D }
##D 
##D # Execute more complex code
##D result <- replr_execute_code(session_id, "
##D   data <- data.frame(x = 1:5, y = letters[1:5])
##D   summary(data)
##D ")
## End(Not run)



cleanEx()
nameEx("replr_execute_code_tool")
### * replr_execute_code_tool

flush(stderr()); flush(stdout())

### Name: replr_execute_code_tool
### Title: Execute Code Tool Definition
### Aliases: replr_execute_code_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D execute_tool <- replr_execute_code_tool()
##D print(execute_tool$name)
## End(Not run)



cleanEx()
nameEx("replr_get_session_info")
### * replr_get_session_info

flush(stderr()); flush(stdout())

### Name: replr_get_session_info
### Title: Get Information About a REPL Session
### Aliases: replr_get_session_info

### ** Examples

## Not run: 
##D # Get information about a session
##D result <- replr_get_session_info("my_session_id")
##D if (result$success) {
##D   print(result$data)
##D }
## End(Not run)



cleanEx()
nameEx("replr_get_session_info_tool")
### * replr_get_session_info_tool

flush(stderr()); flush(stdout())

### Name: replr_get_session_info_tool
### Title: Get Session Info Tool Definition
### Aliases: replr_get_session_info_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D info_tool <- replr_get_session_info_tool()
##D print(info_tool$description)
## End(Not run)



cleanEx()
nameEx("replr_list_sessions")
### * replr_list_sessions

flush(stderr()); flush(stdout())

### Name: replr_list_sessions
### Title: List All Active REPL Sessions
### Aliases: replr_list_sessions

### ** Examples

## Not run: 
##D # List all active sessions
##D result <- replr_list_sessions()
##D if (result$success) {
##D   for (session in result$data$sessions) {
##D     cat("Session:", session$session_id, "- Alive:", session$is_alive, "\n")
##D   }
##D }
## End(Not run)



cleanEx()
nameEx("replr_list_sessions_tool")
### * replr_list_sessions_tool

flush(stderr()); flush(stdout())

### Name: replr_list_sessions_tool
### Title: List Sessions Tool Definition
### Aliases: replr_list_sessions_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D list_tool <- replr_list_sessions_tool()
##D print(list_tool$name)
## End(Not run)



cleanEx()
nameEx("replr_run_r_code")
### * replr_run_r_code

flush(stderr()); flush(stdout())

### Name: replr_run_r_code
### Title: Run R Code (Simple Interface)
### Aliases: replr_run_r_code

### ** Examples

## Not run: 
##D # Execute simple arithmetic
##D result <- replr_run_r_code("2 + 2")
##D if (result$success) {
##D   cat("Output:", result$data$output)
##D }
##D 
##D # Execute more complex code
##D result <- replr_run_r_code("
##D   data <- data.frame(x = 1:5, y = letters[1:5])
##D   summary(data)
##D ")
## End(Not run)



cleanEx()
nameEx("replr_run_r_code_tool")
### * replr_run_r_code_tool

flush(stderr()); flush(stdout())

### Name: replr_run_r_code_tool
### Title: Run R Code Tool Definition
### Aliases: replr_run_r_code_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D run_tool <- replr_run_r_code_tool()
##D print(run_tool$name)
##D print(run_tool$description)
## End(Not run)



cleanEx()
nameEx("replr_stop_all_sessions")
### * replr_stop_all_sessions

flush(stderr()); flush(stdout())

### Name: replr_stop_all_sessions
### Title: Stop All REPL Sessions
### Aliases: replr_stop_all_sessions

### ** Examples

## Not run: 
##D # Stop all sessions at the end of analysis
##D result <- replr_stop_all_sessions()
##D cat("Stopped", result$data$stopped_count, "sessions")
## End(Not run)



cleanEx()
nameEx("replr_stop_all_sessions_tool")
### * replr_stop_all_sessions_tool

flush(stderr()); flush(stdout())

### Name: replr_stop_all_sessions_tool
### Title: Stop All Sessions Tool Definition
### Aliases: replr_stop_all_sessions_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D stop_all_tool <- replr_stop_all_sessions_tool()
##D print(stop_all_tool$description)
## End(Not run)



cleanEx()
nameEx("replr_stop_session")
### * replr_stop_session

flush(stderr()); flush(stdout())

### Name: replr_stop_session
### Title: Stop a REPL Session
### Aliases: replr_stop_session

### ** Examples

## Not run: 
##D # Stop a specific session
##D result <- replr_stop_session("my_session_id")
##D if (result$success) {
##D   cat("Session stopped successfully")
##D }
## End(Not run)



cleanEx()
nameEx("replr_stop_session_tool")
### * replr_stop_session_tool

flush(stderr()); flush(stdout())

### Name: replr_stop_session_tool
### Title: Stop Session Tool Definition
### Aliases: replr_stop_session_tool

### ** Examples

## Not run: 
##D # Get the tool definition
##D stop_tool <- replr_stop_session_tool()
##D print(stop_tool$description)
## End(Not run)



### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
