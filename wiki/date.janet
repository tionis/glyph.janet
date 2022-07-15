(use ./marble)

(defn- _format-date [{:month m :year y :month-day d}]
  (string/format "%.4i-%.2i-%.2i" y (inc m) (inc d)))

(def midnite
  {:hours 0 :minutes 0 :seconds 0})

(def year-start
  {:month 0 :year-day 0 :month 0 :month-day 0})

(def month-start
  {:month-day 0})

(def week-days {:short ["Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"]
                :long ["Sunday" "Monday" "Tuesday" "Wednesday"
                       "Thursday" "Friday" "Saturday"]})
(def months
  {:short
   ["Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"]
   :long
   ["January" "February" "March" "April" "May" "June" "July" "August"
    "September" "October" "November" "December"]})

(def Date
  @{:format _format-date
    :epoch os/mktime
    :str-week-day
    (fn [{:week-day wd} &opt frm]
      (default frm :short)
      (get-in week-days [frm wd]))
    :str-week-day-long
    (fn [{:week-day wd} &opt frm]
      (default frm :long)
      (get-in week-days [frm wd]))
    :str-month
    (fn [{:month m} &opt frm]
      (default frm :short)
      (get-in months [frm m]))
    :str-month-long
    (fn [{:month m} &opt frm]
      (default frm :long)
      (get-in months [frm m]))
    :local (fn [dt] (merge-into dt (os/date (os/mktime dt) true)))})

(def DateTime
  (table/setproto
    @{:format
      (fn [{:month m :year y :month-day d
            :minutes u :hours h :seconds s}]
        (string/format "%s %i:%.2i:%.2i"
                       (_format-date {:month m :year y :month-day d})
                       h u s))
      :date-format _format-date
      :http-format
      (fn [self]
        (def {:month m :year y :month-day d :week-day wd
              :minutes u :hours h :seconds s} (os/date (:epoch self)))
        (string/format "%s, %.2i %s %.4i %i:%.2i:%.2i GMT"
                       (get-in week-days [:short wd]) (inc d)
                       (get-in months [:short m]) y h u s))}
    Date))

(defn- table-date [] (merge (os/date)))
(defn- table-date-local [] (merge (os/date (os/time) true)))

(defn now []
  (make DateTime (table-date)))

(defn now-local []
  (make DateTime (table-date-local)))

(defn today []
  (make Date (merge (table-date) midnite)))

(defn today-local []
  (make Date (merge (table-date-local) midnite)))

(defn- nc [c &opt dc] (fn [n] {c ((if dc dec identity) (scan-number n))}))
(defn- mc [& cs] (merge ;cs))
(def date-time-grammar
  (peg/compile
    ~{:date-sep (set "-/")
      :time-sep ":"
      :date-time-sep (set " T")
      :year (/ '(repeat 4 :d) ,(nc :year))
      :month (/ '(+ (* "0" :d)
                    (* "1" (range "02"))) ,(nc :month true))
      :month-day (/ '(+ (* (range "02") :d)
                        (* "3" (set "01"))) ,(nc :month-day true))
      :hours (/ '(+ (* (set "01") :d)
                    (* "2" (range "03"))) ,(nc :hours))
      :sixty (* (range "05") :d)
      :minutes (/ ':sixty ,(nc :minutes))
      :seconds (/ ':sixty ,(nc :seconds))
      :main (/ (* :year
                  (? (* :date-sep :month
                        (? (* :date-sep :month-day
                              (? (* :date-time-sep
                                    :hours
                                    (? (* :time-sep :minutes
                                          (? (* :time-sep :seconds)))))))))))
               ,mc)}))

(defn from-string [x] # TODO add week-day and year-day
  (merge
    (os/date
      (os/mktime (merge
                    year-start
                    month-start
                    midnite
                    ;(peg/match date-time-grammar x))))
    Date))

(defn normalize [x]
  (case (type x)
    :table x
    :struct (merge x)
    :number (merge (os/date x))
    :string (from-string x)))

(defn make-date [date] # name?
  (def d (normalize date))
  (make Date (merge (os/date (os/mktime (merge d midnite))))))

(defn make-date-time [date-time]
  (def dt (normalize date-time))
  (make DateTime (merge (os/date (os/mktime (merge dt))))))

(def Interval
  @{:format
    (fn [{:duration dur}]
      (def h (math/floor (/ dur 3600)))
      (def m (math/floor (/ (- dur (* h 3600)) 60)))
      (def s (mod dur 60))
      (string/format "%i:%.2i:%.2i" h m s))
    :compare
    (fn [{:duration md} {:duration od}]
      (compare md od))
    :add
    (fn [{:duration md} {:duration od}]
      @{:duration (+ md od)})
    :sub
    (fn [{:duration md} {:duration od}]
      @{:duration (- md od)})
    :in-years
    (fn [{:duration md}]
      (math/floor (/ md (* 60 60 24 365))))
    :in-days
    (fn [{:duration md}]
      (math/floor (/ md (* 60 60 24))))
    :in-hours
    (fn [{:duration md}]
      (math/floor (/ md (* 60 60))))
    :in-minutes
    (fn [{:duration md}]
      (math/floor (/ md (* 60))))})

(defn- secs
  [&opt m]
  (default m 1)
  (fn [t] (* (scan-number t) m)))

(def duration-grammar
  (comptime
    (peg/compile
      ~{:num (range "09")
        :reqwsoe (+ (some :s+) -1)
        :optws (any :s+)
        :secs (/ '(some :num) ,(secs))
        :mins (/ '(some :num) ,(secs 60))
        :hrs (/ '(some :num) ,(secs 3600))
        :tsecs (* :secs :optws (* "s" (any "ec") (any "ond") (any "s")))
        :tmins (* :mins :optws (* "m" (any "in") (any "ute") (any "s")) :optws)
        :thrs (* :hrs :optws (* "h" (+ (any "rs") (any "our"))
                                (any "s")) :optws)
        :text (* (any :thrs) (any :tmins) (any :tsecs))
        :colon (* :hrs ":" :mins (any (if ":" (* ":" :secs))))
        :main (+ (some :text) (some :colon))})))

(defn from-string-dur [s]
  [s]
  (-?> (peg/match duration-grammar s) sum))

(defn minutes [m] (* 60 (or m 0)))
(defn hours [h] (* 60 (minutes h)))
(defn days [d] (* 24 (hours d)))
(defn weeks [d] (* 7 (days d)))
(defn years [y] (* 365 (days y)))

(defn make-interval [interval]
  (make
    Interval
    @{:duration
      (case (type interval)
        :table (interval :duration)
        :number interval
        :struct (cond
                  (interval :duration)
                  (interval :duration)
                  (interval :start)
                  (- (interval :end) (interval :start))
                  (let [{:years y
                         :days d
                         :hours h
                         :minutes m
                         :seconds s} interval]
                    (+ (or s 0) (minutes m)
                       (hours h)
                       (days d)
                       (years y))))
        :string (from-string-dur interval))}))

(def Calendar
  (make
    DateTime
    @{:sooner
      (fn [self interval]
        (make-date-time
          (- (:epoch self)
             ((make-interval interval) :duration))))
      :later
      (fn [self interval]
        (make-date-time
          (+ (:epoch self)
             ((make-interval interval) :duration))))
      :compare
      (fn [self other]
        (compare (:epoch self)
                 (:epoch other)))
      :before?
      (fn [self date-time]
        (compare< self date-time))
      :after?
      (fn [self date-time]
        (compare> self date-time))}))

(defn make-calendar [date-time]
  (make
    Calendar
    (make-date-time date-time)))

(def Period
  (make
    Calendar
    @{:later
      (fn [self interval]
        (make-date-time
          (+ (:epoch self)
             (self :duration)
             ((make-interval interval) :duration))))
      :contains?
      (fn [self date-time]
        (<= (:epoch self)
            (:epoch date-time)
            (:end self)))
      :after?
      (fn [self date-time]
        (< (:epoch date-time)
           (:later self self)))
      :start
      (fn [self] (:epoch self))
      :end
      (fn [self] (+ (:epoch self) (self :duration)))}))

(defn make-period [calendar interval]
  (make
    Period
    (merge (make-calendar calendar)
           (make-interval interval))))

(defn format-date-time [dt &opt local]
  (default local (dyn :local-time))
  (:format (cond-> (make-date-time dt)
                   local :local)))

(defn http-format-date-time [dt]
  (:http-format (make-date-time dt)))

(defn format-date [dt]
  (:format (make-date dt)))

(defn format-interval [i]
  (:format (make-interval i)))

(defn format-time [dt &opt local]
  (def t (cond-> (make-date-time dt)
                 local :local))
  (def h (t :hours))
  (string/format (. "%." (if (zero? h) 1 2) "i:%.2i")
                 h (t :minutes)))

(defn format-today []
  (:format (today)))

(defn format-now []
  (format-date-time (now)))

(defn days-ago [n &opt tdy]
  (default tdy (today))
  (:sooner (make-calendar tdy) (days n)))

(defn days-after [n &opt tdy]
  (default tdy (today))
  (:later (make-calendar tdy) (days n)))

(defn days-ago-local [n &opt tdy]
  (default tdy (today-local))
  (:sooner (make-calendar tdy) (days n)))

(defn days-after-local [n &opt tdy]
  (default tdy (today-local))
  (:later (make-calendar tdy) (days n)))

(defn yesterday [&opt tdy]
  (days-ago 1 tdy))

(defn weeks-ago [n &opt tdy]
  (days-ago (* n 7) tdy))

(defn start-of-week [n &opt tdy]
  (default tdy (today))
  (days-ago (+ (* 7 (- n)) (tdy :week-day)) tdy))

(defn current-week-start [&opt tdy]
  (start-of-week 0 tdy))

(defn last-week-start [&opt tdy]
  (start-of-week -1 tdy))

(defn months-ago [n &opt tdy]
  (default tdy (today)) # TODO fix this and add months-after
  (var ds (tdy :month-day))
  (var me (:sooner (make-calendar (merge tdy month-start)) (days 1)))
  (for i 0 n
    (+= ds (inc (me :month-day)))
    (set me (:sooner (make-calendar (merge me month-start)) (days 1))))
  (days-ago ds tdy))

(defn months-after [n &opt tdy]
  # TODO implement this
  )

(def date/last-weekday [n &opt tdy])

(def date/next-weekday [n &opt tdy])

(defn- set-month-start [d]
  (merge d month-start))

(defn- inc-month [d]
  (merge d (if (= (d :month) 11)
             {:year (inc (d :year)) :month 0}
             {:month (inc (d :month))})))

(defn start-of-month [n &opt tdy]
  (default tdy (today))
  (if (pos? n)
    (do
      (var me (days-ago 1 (set-month-start (inc-month tdy))))
      (var ds (inc (- (me :month-day) (tdy :month-day))))
      (set me (days-after 1 me))
      (for i 1 n
        (set me (days-ago 1 (set-month-start (inc-month me))))
        (+= ds (inc (me :month-day)))
        (set me (days-after 1 me)))
      (days-after ds tdy))
    (do
      (var ds (tdy :month-day))
      (var me (days-ago 1 (set-month-start tdy)))
      (for i 0 (- n)
        (+= ds (inc (me :month-day)))
        (set me (days-ago 1 (set-month-start me))))
      (days-ago ds tdy))))

(defn current-month-start [&opt tdy]
  (start-of-month 0 tdy))

(defn last-month-start [&opt tdy]
  (start-of-month -1 tdy))

(defn start-of-year [n &opt tdy]
  (default tdy (today))
  (make-date (merge tdy {:year (+ (tdy :year) n)} year-start month-start)))

(defn current-year-start [&opt tdy]
  (start-of-year 0 tdy))

(defn human [dt &opt dtn]
  (def cn (make-calendar (or dtn (now))))
  (def cdt (make-calendar dt))
  (cond
    (:contains? (make-period (:sooner cn {:minutes 1}) {:minutes 2}) cdt)
    "now"
    (:contains? (make-period (:sooner cn {:minutes 15}) {:minutes 30}) cdt)
    "about now"
    (:before? (make-calendar (:sooner cn {:hours (cn :hours)})) cdt)
    "today"
    (:before? (make-calendar (:sooner cn {:days 1 :hours (cn :hours)})) cdt)
    "yesterday"
    (:contains? (make-period (:sooner cn {:days 7})
                             {:days 6}) cdt)
    (:str-week-day cdt :long)
    (:contains? (make-period (:sooner cn {:days 28})
                             {:days 27}) cdt)
    (let [dist (math/ceil (/ (- (:epoch cn) (:epoch cdt))
                             (* 7 24 3600)))]
      (string dist " weeks ago"))
    (:contains? (make-period (:sooner cn {:days 364})
                             {:days 338}) cdt)
    (let [dist (math/ceil (/ (- (:epoch cn) (:epoch cdt))
                             (* 30 24 3600)))]
      (string dist " months ago"))
    (= (dec (cn :year)) (cdt :year))
    "last year"))
