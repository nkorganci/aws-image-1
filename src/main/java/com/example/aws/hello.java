package com.example.aws;

// Add proper  imports and a GET mapping to return the string "hello"
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class hello {

    @GetMapping("/hello")
    public String sayHello() {
        return "hello";
    }
}

