test_that("Windows lock probes read process metadata and treat unknown state conservatively", {
  query <- function(command, args, stdout, stderr, timeout) {
    expect_identical(command, "tasklist")
    expect_identical(args, c("/FI", shQuote("PID eq 123"), "/FO", "CSV", "/NH"))
    expect_true(stdout)
    expect_false(stderr)
    expect_identical(timeout, 2)
    '"Rscript.exe","123","Console","1","10,000 K"'
  }
  expect_true(readboj:::outlook_windows_pid_alive(123, query))
  expect_false(readboj:::outlook_windows_pid_alive(123,
    function(...) "INFO: No tasks are running which match the specified criteria."))
  expect_true(readboj:::outlook_windows_pid_alive(123,
    function(...) structure(character(), status = 1L)))
  expect_true(readboj:::outlook_windows_pid_alive(123, function(...) stop("query unavailable")))
  expect_true(readboj:::outlook_pid_alive(Sys.getpid()))
  for (pid in list(NA_real_, Inf, -1, 0, 1.5, numeric(), c(1,2), "123")) {
    expect_true(readboj:::outlook_pid_alive(pid))
  }
})

test_that("Windows native queries distinguish the live reader from an absent PID", {
  skip_on_os(c("linux", "mac", "solaris"))
  expect_true(readboj:::outlook_windows_pid_alive(Sys.getpid()))
  expect_false(readboj:::outlook_windows_pid_alive(.Machine$integer.max))
})
