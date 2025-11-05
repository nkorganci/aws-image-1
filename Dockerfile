# Use Java 17 as base image (or Java 11/21 depending on your project)
FROM eclipse-temurin:17-jdk-alpine

# Set working directory
WORKDIR /app

# Copy the JAR file from target folder
COPY target/*.jar app.jar

# Expose port 8080 (Spring Boot default)
EXPOSE 8081

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]