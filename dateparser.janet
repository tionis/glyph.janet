(import ./date)
(defn to_two_digit_string [num]
  (if (< num 9)
    (string "0" num)
    (string num)))

(defn date->iso8601 [date_to_transform] (string (date_to_transform :year)
                                                "-"
                                                (to_two_digit_string (+ (date_to_transform :month) 1))
                                                "-" 
                                                (to_two_digit_string (+ (date_to_transform :month-day) 1))))

(defn parse-date
  "consumes a date in some semi-natural syntax and returns a struct formatted like {:year :month :day :year-day :month-day :week-day}"
  [date_str & today]
  (default today (date/today-local))
  (cond
    (peg/match ~(* "today" -1) date_str) (date->iso8601 today))
    (peg/match ~(* "tomorrow" -1) date_str) (date->iso8601 (date/days-after-local 1 today))
    (peg/match ~(* "yesterday" -1) date_str) (date->iso8601 (date/days-ago-local 1 today))
    (peg/match ~(* (repeat 4 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) date_str
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string "20" date_str)
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string ((today) :year) "-" date_str)
    (peg/match ~(* (between 1 2 :d) -1) date_str) (string (today :year) "-" (to_two_digit_string (+ (today :month) 1)) "-" date_str)
    (peg/match ~(* (some :d) " day" (opt "s") " ago") date_str)
      (let [days_ago (scan-number ((peg/match ~(* (capture (some :d)) " day" (opt "s") " ago") date_str) 0))]
           (date->iso8601 (date/days-ago-local days_ago today)))
    (peg/match ~(* "in " (some :d) " day" (opt "s")) date_str)
      (let [days_after (scan-number ((peg/match ~(* "in " (capture (some :d)) " day" (opt "s")) date_str) 0))]
           (date->iso8601 (date/days-after-local days_after today)))
    (peg/match ~(* "next week" -1) date_str) (date->iso8601 (date/days-after-local 7 today))
    (peg/match ~(* "last week" -1) date_str) (date->iso8601 (date/days-ago-local 7 today))
    # TODO
    # - $weekday (this week)
    # - $x weeks ago
    # - in $x weeks
    # - last $week_day
    # - next $week_day
    # - next month
    # - last month
    # - in $x months
    # - $x months ago
    (error (string "Could not parse date: " date_str)))
