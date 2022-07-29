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

(def week-days-long (map string/ascii-lower (date/week-days :long)))
(def week-days-short (map string/ascii-lower (date/week-days :short)))

(def get-day-num ((fn []
                   (def ret @{})
                   (loop [i :range [0 (length week-days-long)]]
                     (put ret (week-days-long i) i))
                   (loop [i :range [0 (length week-days-short)]]
                     (put ret (week-days-short i) i))
                   (table/to-struct ret))))

(defn parse-date # TODO precompile PEGs
  "consumes a date in some semi-natural syntax and returns a struct formatted like {:year :month :day :year-day :month-day :week-day}"
  [date_str &opt today]
  (default today (date/today-local))
  (def today (merge today date/DateTime))
  (def date_str (string/ascii-lower date_str))
  (cond
    (peg/match ~(* "today" -1) date_str) (:date-format today)
    (peg/match ~(* "tomorrow" -1) date_str) (:date-format (date/days-after-local 1 today))
    (peg/match ~(* "yesterday" -1) date_str) (:date-format (date/days-ago-local 1 today))
    (peg/match ~(* (repeat 4 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) date_str
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string "20" date_str)
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string (today :year) "-" date_str)
    (peg/match ~(* (between 1 2 :d) -1) date_str) (string (today :year) "-" (to_two_digit_string (+ (today :month) 1)) "-" date_str)
    (peg/match ~(* (some :d) " day" (opt "s") " ago") date_str)
      (let [days_ago (scan-number ((peg/match ~(* (capture (some :d)) " day" (opt "s") " ago") date_str) 0))]
           (:date-format (date/days-ago-local days_ago today)))
    (peg/match ~(* "in " (some :d) " day" (opt "s")) date_str)
      (let [days_after (scan-number ((peg/match ~(* "in " (capture (some :d)) " day" (opt "s")) date_str) 0))]
           (:date-format (date/days-after-local days_after today)))
    (peg/match ~(* "next week" -1) date_str) (:date-format (date/days-after-local 7 today))
    (peg/match ~(* "last week" -1) date_str) (:date-format (date/days-ago-local 7 today))
    (peg/match ~(* "next month" -1) date_str) (:date-format (date/months-after 1 today))
    (peg/match ~(* "last month" -1) date_str) (:date-format (date/months-ago 1 today))
    (peg/match ~(* (some :d) " months ago" -1) date_str)
      (:date-format (date/months-ago (scan-number ((peg/match ~(* (capture (any :d)) " months ago" -1) date_str) 0)) today))
    (peg/match ~(* "in " (some :d) " months" -1) date_str)
      (:date-format (date/months-ago (scan-number ((peg/match ~(* "in " (capture (any :d)) " months" -1) date_str) 0)) today))
    (peg/match ~(+ ,;week-days-short ,;week-days-long) date_str)
      (:date-format (merge today {:week-day (get-day-num date_str)}))
    (peg/match ~(* (some :d) " weeks ago") date_str)
      (:date-format (date/weeks-ago (scan-number ((peg/match ~(* (capture (some :d)) " weeks ago") date_str) 0)) today))
    (peg/match ~(* "in " (some :d) " weeks ago") date_str)
      (:date-format (date/weeks-ago (scan-number ((peg/match ~(* "in " (capture (some :d)) " weeks") date_str) 0)) today))
    (peg/match ~(* "last " (+ ,;week-days-short ,;week-days-long)) date_str)
      (:date-format (date/last-weekday
                      (get-day-num (scan-number ((peg/match 
                                                    ~(* "last " (capture (+ ,;week-days-short ,;week-days-long)))
                                                    date_str) 0)))
                      today))
    (peg/match ~(* "next " (+ ,;week-days-short ,;week-days-long)) date_str)
      (:date-format (date/next-weekday
                      (get-day-num (scan-number ((peg/match
                                                   ~(* "next " (capture (+ ,;week-days-short ,;week-days-long)))
                                                    date_str) 0)))
                      today))
    (error (string "Could not parse date: " date_str))))
