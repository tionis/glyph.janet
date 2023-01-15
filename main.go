package main

import (
	"fmt"
	"github.com/tj/go-naturaldate"
	"log"
	"time"
)

func main() {
	text := "2022-12-04T20:00"
	parsed, err := naturaldate.Parse(text, time.Now())
	if err != nil {
		log.Panic(err)
	}
	fmt.Println(parsed)
}
