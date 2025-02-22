# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

skip_if_not_available("dataset")
skip_if_not_available("utf8proc")

library(dplyr, warn.conflicts = FALSE)
library(lubridate)
library(stringr)
library(stringi)

test_that("paste, paste0, and str_c", {
  df <- tibble(
    v = c("A", "B", "C"),
    w = c("a", "b", "c"),
    x = c("d", NA_character_, "f"),
    y = c(NA_character_, "h", "i"),
    z = c(1.1, 2.2, NA)
  )
  x <- Expression$field_ref("x")
  y <- Expression$field_ref("y")

  # no NAs in data
  compare_dplyr_binding(
    .input %>%
      transmute(paste(v, w)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(paste(v, w, sep = "-")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(paste0(v, w)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(str_c(v, w)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(str_c(v, w, sep = "+")) %>%
      collect(),
    df
  )

  # NAs in data
  compare_dplyr_binding(
    .input %>%
      transmute(paste(x, y)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(paste(x, y, sep = "-")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(str_c(x, y)) %>%
      collect(),
    df
  )

  # non-character column in dots
  compare_dplyr_binding(
    .input %>%
      transmute(paste0(x, y, z)) %>%
      collect(),
    df
  )

  # literal string in dots
  compare_dplyr_binding(
    .input %>%
      transmute(paste(x, "foo", y)) %>%
      collect(),
    df
  )

  # literal NA in dots
  compare_dplyr_binding(
    .input %>%
      transmute(paste(x, NA, y)) %>%
      collect(),
    df
  )

  # expressions in dots
  compare_dplyr_binding(
    .input %>%
      transmute(paste0(x, toupper(y), as.character(z))) %>%
      collect(),
    df
  )

  # sep is literal NA
  # errors in paste() (consistent with base::paste())
  expect_error(
    nse_funcs$paste(x, y, sep = NA_character_),
    "Invalid separator"
  )
  # emits null in str_c() (consistent with stringr::str_c())
  compare_dplyr_binding(
    .input %>%
      transmute(str_c(x, y, sep = NA_character_)) %>%
      collect(),
    df
  )

  # sep passed in dots to paste0 (which doesn't take a sep argument)
  compare_dplyr_binding(
    .input %>%
      transmute(paste0(x, y, sep = "-")) %>%
      collect(),
    df
  )

  # known differences

  # arrow allows the separator to be an array
  expect_equal(
    df %>%
      Table$create() %>%
      transmute(result = paste(x, y, sep = w)) %>%
      collect(),
    df %>%
      transmute(result = paste(x, w, y, sep = ""))
  )

  # expected errors

  # collapse argument not supported
  expect_error(
    nse_funcs$paste(x, y, collapse = ""),
    "collapse"
  )
  expect_error(
    nse_funcs$paste0(x, y, collapse = ""),
    "collapse"
  )
  expect_error(
    nse_funcs$str_c(x, y, collapse = ""),
    "collapse"
  )

  # literal vectors of length != 1 not supported
  expect_error(
    nse_funcs$paste(x, character(0), y),
    "Literal vectors of length != 1 not supported in string concatenation"
  )
  expect_error(
    nse_funcs$paste(x, c(",", ";"), y),
    "Literal vectors of length != 1 not supported in string concatenation"
  )
})

test_that("grepl with ignore.case = FALSE and fixed = TRUE", {
  df <- tibble(x = c("Foo", "bar"))
  compare_dplyr_binding(
    .input %>%
      filter(grepl("o", x, fixed = TRUE)) %>%
      collect(),
    df
  )
})

test_that("sub and gsub with ignore.case = FALSE and fixed = TRUE", {
  df <- tibble(x = c("Foo", "bar"))
  compare_dplyr_binding(
    .input %>%
      transmute(x = sub("Foo", "baz", x, fixed = TRUE)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = gsub("o", "u", x, fixed = TRUE)) %>%
      collect(),
    df
  )
})

# many of the remainder of these tests require RE2
skip_if_not_available("re2")

test_that("grepl", {
  df <- tibble(x = c("Foo", "bar"))

  for (fixed in c(TRUE, FALSE)) {
    compare_dplyr_binding(
      .input %>%
        filter(grepl("Foo", x, fixed = fixed)) %>%
        collect(),
      df
    )
    compare_dplyr_binding(
      .input %>%
        transmute(x = grepl("^B.+", x, ignore.case = FALSE, fixed = fixed)) %>%
        collect(),
      df
    )
    compare_dplyr_binding(
      .input %>%
        filter(grepl("Foo", x, ignore.case = FALSE, fixed = fixed)) %>%
        collect(),
      df
    )
  }
})

test_that("grepl with ignore.case = TRUE and fixed = TRUE", {
  df <- tibble(x = c("Foo", "bar"))

  # base::grepl() ignores ignore.case = TRUE with a warning when fixed = TRUE,
  # so we can't use compare_dplyr_binding() for these tests
  expect_equal(
    df %>%
      Table$create() %>%
      filter(grepl("O", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = "Foo")
  )
  expect_equal(
    df %>%
      Table$create() %>%
      filter(x = grepl("^B.+", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = character(0))
  )
})

test_that("str_detect", {
  df <- tibble(x = c("Foo", "bar"))

  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, regex("^F"))) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_detect(x, regex("^f[A-Z]{2}", ignore_case = TRUE))) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_detect(x, regex("^f[A-Z]{2}", ignore_case = TRUE), negate = TRUE)) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, fixed("o"))) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, fixed("O"))) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, fixed("O", ignore_case = TRUE))) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, fixed("O", ignore_case = TRUE), negate = TRUE)) %>%
      collect(),
    df
  )
})

test_that("sub and gsub", {
  df <- tibble(x = c("Foo", "bar"))

  for (fixed in c(TRUE, FALSE)) {
    compare_dplyr_binding(
      .input %>%
        transmute(x = sub("Foo", "baz", x, fixed = fixed)) %>%
        collect(),
      df
    )
    compare_dplyr_binding(
      .input %>%
        transmute(x = sub("^B.+", "baz", x, ignore.case = FALSE, fixed = fixed)) %>%
        collect(),
      df
    )
    compare_dplyr_binding(
      .input %>%
        transmute(x = sub("Foo", "baz", x, ignore.case = FALSE, fixed = fixed)) %>%
        collect(),
      df
    )
  }
})

test_that("sub and gsub with ignore.case = TRUE and fixed = TRUE", {
  df <- tibble(x = c("Foo", "bar"))

  # base::sub() and base::gsub() ignore ignore.case = TRUE with a warning when
  # fixed = TRUE, so we can't use compare_dplyr_binding() for these tests
  expect_equal(
    df %>%
      Table$create() %>%
      transmute(x = sub("O", "u", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = c("Fuo", "bar"))
  )
  expect_equal(
    df %>%
      Table$create() %>%
      transmute(x = gsub("o", "u", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = c("Fuu", "bar"))
  )
  expect_equal(
    df %>%
      Table$create() %>%
      transmute(x = sub("^B.+", "baz", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    df # unchanged
  )
})

test_that("str_replace and str_replace_all", {
  df <- tibble(x = c("Foo", "bar"))

  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace_all(x, "^F", "baz")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace_all(x, regex("^F"), "baz")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_replace(x, "^F[a-z]{2}", "baz")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, regex("^f[A-Z]{2}", ignore_case = TRUE), "baz")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace_all(x, fixed("o"), "u")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, fixed("O"), "u")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, fixed("O", ignore_case = TRUE), "u")) %>%
      collect(),
    df
  )
})

test_that("strsplit and str_split", {
  df <- tibble(x = c("Foo and bar", "baz and qux and quux"))

  compare_dplyr_binding(
    .input %>%
      mutate(x = strsplit(x, "and")) %>%
      collect(),
    df,
    # `ignore_attr = TRUE` because the vctr coming back from arrow (ListArray)
    # has type information in it, but it's just a bare list from R/dplyr.
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = strsplit(x, "and.*", fixed = TRUE)) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = strsplit(x, " +and +")) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_split(x, "and")) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_split(x, "and", n = 2)) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_split(x, fixed("and"), n = 2)) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_split(x, regex("and"), n = 2)) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_split(x, "Foo|bar", n = 2)) %>%
      collect(),
    df,
    ignore_attr = TRUE
  )
})

test_that("strrep and str_dup", {
  df <- tibble(x = c("foo1", " \tB a R\n", "!apACHe aRroW!"))
  for (times in 0:8) {
    compare_dplyr_binding(
      .input %>%
        mutate(x = strrep(x, times)) %>%
        collect(),
      df
    )

    compare_dplyr_binding(
      .input %>%
        mutate(x = str_dup(x, times)) %>%
        collect(),
      df
    )
  }
})

test_that("str_to_lower, str_to_upper, and str_to_title", {
  df <- tibble(x = c("foo1", " \tB a R\n", "!apACHe aRroW!"))
  compare_dplyr_binding(
    .input %>%
      transmute(
        x_lower = str_to_lower(x),
        x_upper = str_to_upper(x),
        x_title = str_to_title(x)
      ) %>%
      collect(),
    df
  )

  # Error checking a single function because they all use the same code path.
  expect_error(
    nse_funcs$str_to_lower("Apache Arrow", locale = "sp"),
    "Providing a value for 'locale' other than the default ('en') is not supported in Arrow",
    fixed = TRUE
  )
})

test_that("arrow_*_split_whitespace functions", {
  # use only ASCII whitespace characters
  df_ascii <- tibble(x = c("Foo\nand bar", "baz\tand qux and quux"))

  # use only non-ASCII whitespace characters
  df_utf8 <- tibble(x = c("Foo\u00A0and\u2000bar", "baz\u2006and\u1680qux\u3000and\u2008quux"))

  df_split <- tibble(x = list(c("Foo", "and", "bar"), c("baz", "and", "qux", "and", "quux")))

  # use default option values
  expect_equal(
    df_ascii %>%
      Table$create() %>%
      mutate(x = arrow_ascii_split_whitespace(x)) %>%
      collect(),
    df_split,
    ignore_attr = TRUE
  )
  expect_equal(
    df_utf8 %>%
      Table$create() %>%
      mutate(x = arrow_utf8_split_whitespace(x)) %>%
      collect(),
    df_split,
    ignore_attr = TRUE
  )

  # specify non-default option values
  expect_equal(
    df_ascii %>%
      Table$create() %>%
      mutate(
        x = arrow_ascii_split_whitespace(x, options = list(max_splits = 1, reverse = TRUE))
      ) %>%
      collect(),
    tibble(x = list(c("Foo\nand", "bar"), c("baz\tand qux and", "quux"))),
    ignore_attr = TRUE
  )
  expect_equal(
    df_utf8 %>%
      Table$create() %>%
      mutate(
        x = arrow_utf8_split_whitespace(x, options = list(max_splits = 1, reverse = TRUE))
      ) %>%
      collect(),
    tibble(x = list(c("Foo\u00A0and", "bar"), c("baz\u2006and\u1680qux\u3000and", "quux"))),
    ignore_attr = TRUE
  )
})

test_that("errors and warnings in string splitting", {
  # These conditions generate an error, but abandon_ship() catches the error,
  # issues a warning, and pulls the data into R (if computing on InMemoryDataset)
  # Elsewhere we test that abandon_ship() works,
  # so here we can just call the functions directly

  x <- Expression$field_ref("x")
  expect_error(
    nse_funcs$str_split(x, fixed("and", ignore_case = TRUE)),
    "Case-insensitive string splitting not supported in Arrow"
  )
  expect_error(
    nse_funcs$str_split(x, coll("and.?")),
    "Pattern modifier `coll()` not supported in Arrow",
    fixed = TRUE
  )
  expect_error(
    nse_funcs$str_split(x, boundary(type = "word")),
    "Pattern modifier `boundary()` not supported in Arrow",
    fixed = TRUE
  )
  expect_error(
    nse_funcs$str_split(x, "and", n = 0),
    "Splitting strings into zero parts not supported in Arrow"
  )

  # This condition generates a warning
  expect_warning(
    nse_funcs$str_split(x, fixed("and"), simplify = TRUE),
    "Argument 'simplify = TRUE' will be ignored"
  )
})

test_that("errors and warnings in string detection and replacement", {
  x <- Expression$field_ref("x")

  expect_error(
    nse_funcs$str_detect(x, boundary(type = "character")),
    "Pattern modifier `boundary()` not supported in Arrow",
    fixed = TRUE
  )
  expect_error(
    nse_funcs$str_replace_all(x, coll("o", locale = "en"), "ó"),
    "Pattern modifier `coll()` not supported in Arrow",
    fixed = TRUE
  )

  # This condition generates a warning
  expect_warning(
    nse_funcs$str_replace_all(x, regex("o", multiline = TRUE), "u"),
    "Ignoring pattern modifier argument not supported in Arrow: \"multiline\""
  )
})

test_that("backreferences in pattern in string detection", {
  skip("RE2 does not support backreferences in pattern (https://github.com/google/re2/issues/101)")
  df <- tibble(x = c("Foo", "bar"))

  compare_dplyr_binding(
    .input %>%
      filter(str_detect(x, regex("F([aeiou])\\1"))) %>%
      collect(),
    df
  )
})

test_that("backreferences (substitutions) in string replacement", {
  df <- tibble(x = c("Foo", "bar"))

  compare_dplyr_binding(
    .input %>%
      transmute(desc = sub(
        "(?:https?|ftp)://([^/\r\n]+)(/[^\r\n]*)?",
        "path `\\2` on server `\\1`",
        url
      )) %>%
      collect(),
    tibble(url = "https://arrow.apache.org/docs/r/")
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, "^(\\w)o(.*)", "\\1\\2p")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, regex("^(\\w)o(.*)", ignore_case = TRUE), "\\1\\2p")) %>%
      collect(),
    df
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = str_replace(x, regex("^(\\w)o(.*)", ignore_case = TRUE), "\\1\\2p")) %>%
      collect(),
    df
  )
})

test_that("edge cases in string detection and replacement", {
  # in case-insensitive fixed match/replace, test that "\\E" in the search
  # string and backslashes in the replacement string are interpreted literally.
  # this test does not use compare_dplyr_binding() because base::sub() and
  # base::grepl() do not support ignore.case = TRUE when fixed = TRUE.
  expect_equal(
    tibble(x = c("\\Q\\e\\D")) %>%
      Table$create() %>%
      filter(grepl("\\E", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = c("\\Q\\e\\D"))
  )
  expect_equal(
    tibble(x = c("\\Q\\e\\D")) %>%
      Table$create() %>%
      transmute(x = sub("\\E", "\\L", x, ignore.case = TRUE, fixed = TRUE)) %>%
      collect(),
    tibble(x = c("\\Q\\L\\D"))
  )

  # test that a user's "(?i)" prefix does not break the "(?i)" prefix that's
  # added in case-insensitive regex match/replace
  compare_dplyr_binding(
    .input %>%
      filter(grepl("(?i)^[abc]{3}$", x, ignore.case = TRUE, fixed = FALSE)) %>%
      collect(),
    tibble(x = c("ABC"))
  )
  compare_dplyr_binding(
    .input %>%
      transmute(x = sub("(?i)^[abc]{3}$", "123", x, ignore.case = TRUE, fixed = FALSE)) %>%
      collect(),
    tibble(x = c("ABC"))
  )
})

test_that("strptime", {
  # base::strptime() defaults to local timezone
  # but arrow's strptime defaults to UTC.
  # So that tests are consistent, set the local timezone to UTC
  # TODO: consider reevaluating this workaround after ARROW-12980
  withr::local_timezone("UTC")

  t_string <- tibble(x = c("2018-10-07 19:04:05", NA))
  t_stamp <- tibble(x = c(lubridate::ymd_hms("2018-10-07 19:04:05"), NA))

  expect_equal(
    t_string %>%
      Table$create() %>%
      mutate(
        x = strptime(x)
      ) %>%
      collect(),
    t_stamp,
    ignore_attr = "tzone"
  )

  expect_equal(
    t_string %>%
      Table$create() %>%
      mutate(
        x = strptime(x, format = "%Y-%m-%d %H:%M:%S")
      ) %>%
      collect(),
    t_stamp,
    ignore_attr = "tzone"
  )

  expect_equal(
    t_string %>%
      Table$create() %>%
      mutate(
        x = strptime(x, format = "%Y-%m-%d %H:%M:%S", unit = "ns")
      ) %>%
      collect(),
    t_stamp,
    ignore_attr = "tzone"
  )

  expect_equal(
    t_string %>%
      Table$create() %>%
      mutate(
        x = strptime(x, format = "%Y-%m-%d %H:%M:%S", unit = "s")
      ) %>%
      collect(),
    t_stamp,
    ignore_attr = "tzone"
  )

  tstring <- tibble(x = c("08-05-2008", NA))
  tstamp <- strptime(c("08-05-2008", NA), format = "%m-%d-%Y")

  expect_equal(
    tstring %>%
      Table$create() %>%
      mutate(
        x = strptime(x, format = "%m-%d-%Y")
      ) %>%
      pull(),
    # R's strptime returns POSIXlt (list type)
    as.POSIXct(tstamp),
    ignore_attr = "tzone"
  )
})

test_that("errors in strptime", {
  # Error when tz is passed
  x <- Expression$field_ref("x")
  expect_error(
    nse_funcs$strptime(x, tz = "PDT"),
    "Time zone argument not supported in Arrow"
  )
})

test_that("strftime", {
  skip_on_os("windows") # https://issues.apache.org/jira/browse/ARROW-13168

  times <- tibble(
    datetime = c(lubridate::ymd_hms("2018-10-07 19:04:05", tz = "Etc/GMT+6"), NA),
    date = c(as.Date("2021-01-01"), NA)
  )
  formats <- "%a %A %w %d %b %B %m %y %Y %H %I %p %M %z %Z %j %U %W %x %X %% %G %V %u"
  formats_date <- "%a %A %w %d %b %B %m %y %Y %H %I %p %M %j %U %W %x %X %% %G %V %u"

  compare_dplyr_binding(
    .input %>%
      mutate(x = strftime(datetime, format = formats)) %>%
      collect(),
    times
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = strftime(date, format = formats_date)) %>%
      collect(),
    times
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = strftime(datetime, format = formats, tz = "Pacific/Marquesas")) %>%
      collect(),
    times
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = strftime(datetime, format = formats, tz = "EST", usetz = TRUE)) %>%
      collect(),
    times
  )

  withr::with_timezone(
    "Pacific/Marquesas",
    {
      compare_dplyr_binding(
        .input %>%
          mutate(
            x = strftime(datetime, format = formats, tz = "EST"),
            x_date = strftime(date, format = formats_date, tz = "EST")
          ) %>%
          collect(),
        times
      )

      compare_dplyr_binding(
        .input %>%
          mutate(
            x = strftime(datetime, format = formats),
            x_date = strftime(date, format = formats_date)
          ) %>%
          collect(),
        times
      )
    }
  )

  # This check is due to differences in the way %c currently works in Arrow and R's strftime.
  # We can revisit after https://github.com/HowardHinnant/date/issues/704 is resolved.
  expect_error(
    times %>%
      Table$create() %>%
      mutate(x = strftime(datetime, format = "%c")) %>%
      collect(),
    "%c flag is not supported in non-C locales."
  )

  # Output precision of %S depends on the input timestamp precision.
  # Timestamps with second precision are represented as integers while
  # milliseconds, microsecond and nanoseconds are represented as fixed floating
  # point numbers with 3, 6 and 9 decimal places respectively.
  compare_dplyr_binding(
    .input %>%
      mutate(x = strftime(datetime, format = "%S")) %>%
      transmute(as.double(substr(x, 1, 2))) %>%
      collect(),
    times,
    tolerance = 1e-6
  )
})

test_that("format_ISO8601", {
  skip_on_os("windows") # https://issues.apache.org/jira/browse/ARROW-13168
  times <- tibble(x = c(lubridate::ymd_hms("2018-10-07 19:04:05", tz = "Etc/GMT+6"), NA))

  compare_dplyr_binding(
    .input %>%
      mutate(x = format_ISO8601(x, precision = "ymd", usetz = FALSE)) %>%
      collect(),
    times
  )

  if (getRversion() < "3.5") {
    # before 3.5, times$x will have no timezone attribute, so Arrow faithfully
    # errors that there is no timezone to format:
    expect_error(
      times %>%
        Table$create() %>%
        mutate(x = format_ISO8601(x, precision = "ymd", usetz = TRUE)) %>%
        collect(),
      "Timezone not present, cannot convert to string with timezone: %Y-%m-%d%z"
    )

    # See comment regarding %S flag in strftime tests
    expect_error(
      times %>%
        Table$create() %>%
        mutate(x = format_ISO8601(x, precision = "ymdhms", usetz = TRUE)) %>%
        mutate(x = gsub("\\.0*", "", x)) %>%
        collect(),
      "Timezone not present, cannot convert to string with timezone: %Y-%m-%dT%H:%M:%S%z"
    )
  } else {
    compare_dplyr_binding(
      .input %>%
        mutate(x = format_ISO8601(x, precision = "ymd", usetz = TRUE)) %>%
        collect(),
      times
    )

    # See comment regarding %S flag in strftime tests
    compare_dplyr_binding(
      .input %>%
        mutate(x = format_ISO8601(x, precision = "ymdhms", usetz = TRUE)) %>%
        mutate(x = gsub("\\.0*", "", x)) %>%
        collect(),
      times
    )
  }


  # See comment regarding %S flag in strftime tests
  compare_dplyr_binding(
    .input %>%
      mutate(x = format_ISO8601(x, precision = "ymdhms", usetz = FALSE)) %>%
      mutate(x = gsub("\\.0*", "", x)) %>%
      collect(),
    times
  )
})

test_that("arrow_find_substring and arrow_find_substring_regex", {
  df <- tibble(x = c("Foo and Bar", "baz and qux and quux"))

  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = arrow_find_substring(x, options = list(pattern = "b"))) %>%
      collect(),
    tibble(x = c(-1, 0))
  )
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = arrow_find_substring(
        x,
        options = list(pattern = "b", ignore_case = TRUE)
      )) %>%
      collect(),
    tibble(x = c(8, 0))
  )
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = arrow_find_substring_regex(
        x,
        options = list(pattern = "^[fb]")
      )) %>%
      collect(),
    tibble(x = c(-1, 0))
  )
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = arrow_find_substring_regex(
        x,
        options = list(pattern = "[AEIOU]", ignore_case = TRUE)
      )) %>%
      collect(),
    tibble(x = c(1, 1))
  )
})

test_that("stri_reverse and arrow_ascii_reverse functions", {
  df_ascii <- tibble(x = c("Foo\nand bar", "baz\tand qux and quux"))

  df_utf8 <- tibble(x = c("Foo\u00A0\u0061nd\u00A0bar", "\u0062az\u00A0and\u00A0qux\u3000and\u00A0quux"))

  compare_dplyr_binding(
    .input %>%
      mutate(x = stri_reverse(x)) %>%
      collect(),
    df_utf8
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = stri_reverse(x)) %>%
      collect(),
    df_ascii
  )

  expect_equal(
    df_ascii %>%
      Table$create() %>%
      mutate(x = arrow_ascii_reverse(x)) %>%
      collect(),
    tibble(x = c("rab dna\nooF", "xuuq dna xuq dna\tzab"))
  )

  expect_error(
    df_utf8 %>%
      Table$create() %>%
      mutate(x = arrow_ascii_reverse(x)) %>%
      collect(),
    "Invalid: Non-ASCII sequence in input"
  )
})

test_that("str_like", {
  df <- tibble(x = c("Foo and bar", "baz and qux and quux"))

  # TODO: After new version of stringr with str_like has been released, update all
  # these tests to use compare_dplyr_binding

  # No match - entire string
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = str_like(x, "baz")) %>%
      collect(),
    tibble(x = c(FALSE, FALSE))
  )

  # Match - entire string
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = str_like(x, "Foo and bar")) %>%
      collect(),
    tibble(x = c(TRUE, FALSE))
  )

  # Wildcard
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = str_like(x, "f%", ignore_case = TRUE)) %>%
      collect(),
    tibble(x = c(TRUE, FALSE))
  )

  # Ignore case
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = str_like(x, "f%", ignore_case = FALSE)) %>%
      collect(),
    tibble(x = c(FALSE, FALSE))
  )

  # Single character
  expect_equal(
    df %>%
      Table$create() %>%
      mutate(x = str_like(x, "_a%")) %>%
      collect(),
    tibble(x = c(FALSE, TRUE))
  )

  # This will give an error until a new version of stringr with str_like has been released
  skip_if_not(packageVersion("stringr") > "1.4.0")
  compare_dplyr_binding(
    .input %>%
      mutate(x = str_like(x, "%baz%")) %>%
      collect(),
    df
  )
})

test_that("str_pad", {
  df <- tibble(x = c("Foo and bar", "baz and qux and quux"))

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_pad(x, width = 31)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_pad(x, width = 30, side = "right")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_pad(x, width = 31, side = "left", pad = "+")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_pad(x, width = 10, side = "left", pad = "+")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(x = str_pad(x, width = 31, side = "both")) %>%
      collect(),
    df
  )
})

test_that("substr", {
  df <- tibble(x = "Apache Arrow")

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 0, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, -1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 6, 1)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, -1, -2)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 9, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, 8, 12)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = substr(x, -5, -1)) %>%
      collect(),
    df
  )

  expect_error(
    nse_funcs$substr("Apache Arrow", c(1, 2), 3),
    "`start` must be length 1 - other lengths are not supported in Arrow"
  )

  expect_error(
    nse_funcs$substr("Apache Arrow", 1, c(2, 3)),
    "`stop` must be length 1 - other lengths are not supported in Arrow"
  )
})

test_that("substring", {
  # nse_funcs$substring just calls nse_funcs$substr, tested extensively above
  df <- tibble(x = "Apache Arrow")

  compare_dplyr_binding(
    .input %>%
      mutate(y = substring(x, 1, 6)) %>%
      collect(),
    df
  )
})

test_that("str_sub", {
  df <- tibble(x = "Apache Arrow")

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 0, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, -1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 6, 1)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, -1, -2)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, -1, 3)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 9, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 1, 6)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, 8, 12)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(y = str_sub(x, -5, -1)) %>%
      collect(),
    df
  )

  expect_error(
    nse_funcs$str_sub("Apache Arrow", c(1, 2), 3),
    "`start` must be length 1 - other lengths are not supported in Arrow"
  )

  expect_error(
    nse_funcs$str_sub("Apache Arrow", 1, c(2, 3)),
    "`end` must be length 1 - other lengths are not supported in Arrow"
  )
})

test_that("str_starts, str_ends, startsWith, endsWith", {
  df <- tibble(x = c("Foo", "bar", "baz", "qux"))

  compare_dplyr_binding(
    .input %>%
      filter(str_starts(x, "b.*")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_starts(x, "b.*", negate = TRUE)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_starts(x, fixed("b.*"))) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_starts(x, fixed("b"))) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_ends(x, "r")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_ends(x, "r", negate = TRUE)) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_ends(x, fixed("r$"))) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(str_ends(x, fixed("r"))) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(startsWith(x, "b")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(endsWith(x, "r")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(startsWith(x, "b.*")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      filter(endsWith(x, "r$")) %>%
      collect(),
    df
  )
})

test_that("str_count", {
  df <- tibble(
    cities = c("Kolkata", "Dar es Salaam", "Tel Aviv", "San Antonio", "Cluj Napoca", "Bern", "Bogota"),
    dots = c("a.", "...", ".a.a", "a..a.", "ab...", "dse....", ".f..d..")
  )

  compare_dplyr_binding(
    .input %>%
      mutate(a_count = str_count(cities, pattern = "a")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(p_count = str_count(cities, pattern = "d")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(p_count = str_count(cities,
        pattern = regex("d", ignore_case = TRUE)
      )) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(e_count = str_count(cities, pattern = "u")) %>%
      collect(),
    df
  )

  # nse_funcs$str_count() is not vectorised over pattern
  compare_dplyr_binding(
    .input %>%
      mutate(let_count = str_count(cities, pattern = c("a", "b", "e", "g", "p", "n", "s"))) %>%
      collect(),
    df,
    warning = TRUE
  )

  compare_dplyr_binding(
    .input %>%
      mutate(dots_count = str_count(dots, ".")) %>%
      collect(),
    df
  )

  compare_dplyr_binding(
    .input %>%
      mutate(dots_count = str_count(dots, fixed("."))) %>%
      collect(),
    df
  )
})
