package com.example.aws;

// Add proper  imports and a GET mapping to return the string "hello"
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.net.InetAddress;
import java.net.UnknownHostException;

@RestController
public class hello {

    @GetMapping("/hello")
    public String sayHello() {
        try {
            // Get the local hostname and IP address
            InetAddress inetAddress = InetAddress.getLocalHost();
            String ipAddress = inetAddress.getHostAddress();
            String hostname = inetAddress.getHostName();

            return String.format("Hello from EC2 Instance - IP: %s (Hostname: %s)", ipAddress, hostname);
        } catch (UnknownHostException e) {
            return "Hello from EC2 Instance - Unable to determine IP: " + e.getMessage();
        }
    }
}
// good jobs

