# ==============================================================================
# DOCKER IMAGE FOR SPRING BOOT APPLICATION
# ==============================================================================
#
# PURPOSE: Creates a containerized environment to run the Spring Boot application
#          with all dependencies and Java runtime included.
#
# USAGE: docker build -t nkorganci/hello-aws:latest .
#        docker run -d -p 8081:8081 --name helloaws nkorganci/hello-aws:latest
#
# ==============================================================================

FROM eclipse-temurin:17-jdk-alpine
# WHAT: Base image with Java 17 JDK on Alpine Linux
# WHY:
#   - eclipse-temurin: Open-source Java distribution (recommended by Spring Boot)
#   - 17: Java version required by Spring Boot 3.x
#   - jdk: Full JDK (includes tools for debugging)
#   - alpine: Lightweight Linux distro (~5MB vs ~100MB for regular images)
# WITHOUT: No Java runtime, cannot run Spring Boot application
# ALTERNATIVES:
#   - eclipse-temurin:17-jre-alpine (smaller, JRE only, no debugging tools)
#   - amazoncorretto:17-alpine (AWS-maintained Java distribution)
#   - openjdk:17-alpine (older, less maintained)
# BEST PRACTICE: Use JRE for production (smaller), JDK for dev/debugging

WORKDIR /app
# WHAT: Sets working directory inside container to /app
# WHY: All subsequent commands (COPY, ENTRYPOINT) execute from this directory
# WITHOUT: Files copied to root directory (/), messy and not organized
# BEST PRACTICE: Always use WORKDIR for organized file structure

COPY target/*.jar app.jar
# WHAT: Copies JAR file from target/ directory to container as app.jar
# WHY:
#   - target/*.jar: Maven build output location (built by Jenkins)
#   - app.jar: Simplified name for easier reference in ENTRYPOINT
# WITHOUT: No application code in container, image is useless
# NOTE: This requires Maven build to complete BEFORE docker build
# BEST PRACTICE: Use multi-stage builds to compile inside Docker:
#   FROM maven:3.9-eclipse-temurin-17 AS build
#   WORKDIR /app
#   COPY pom.xml .
#   COPY src ./src
#   RUN mvn clean package -DskipTests
#
#   FROM eclipse-temurin:17-jre-alpine
#   COPY --from=build /app/target/*.jar app.jar
# WHY: Self-contained build, no Maven required on Jenkins

EXPOSE 8081
# WHAT: Documents that container listens on port 8081
# WHY:
#   - Port 8081 is configured in application.properties (server.port=8081)
#   - Informs users which port to map when running container
# WITHOUT: Container still works, but no documentation of port usage
# NOTE: This is documentation only, doesn't actually publish the port
# BEST PRACTICE: Always document exposed ports for clarity
# TO PUBLISH: Use -p flag when running: docker run -p 8081:8081

ENTRYPOINT ["java", "-jar", "app.jar"]
# WHAT: Defines the command to run when container starts
# WHY:
#   - java: Executes Java runtime
#   - -jar: Specifies JAR file to run
#   - app.jar: The Spring Boot application file
# WITHOUT: Container starts but does nothing, exits immediately
# ENTRYPOINT vs CMD:
#   - ENTRYPOINT: Command always runs, cannot be overridden easily
#   - CMD: Default command, can be overridden with docker run
# BEST PRACTICE: Use ENTRYPOINT for main app, CMD for default arguments
# PRODUCTION OPTIMIZATION: Add JVM flags for performance:
#   ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
# WHY:
#   -XX:+UseContainerSupport: Respects container memory limits
#   -XX:MaxRAMPercentage=75.0: Uses up to 75% of container memory for heap
#   WITHOUT: Java might use too much memory, container gets killed (OOMKilled)

# ==============================================================================
# DOCKERFILE BEST PRACTICES & IMPROVEMENTS TO CONSIDER
# ==============================================================================
#
# ✅ CURRENT GOOD PRACTICES:
# 1. Using Alpine Linux (small image size)
# 2. Using official Eclipse Temurin Java distribution
# 3. Simple, clear structure
# 4. Documented port exposure
#
# 🔧 RECOMMENDED IMPROVEMENTS:
#
# 1. USE MULTI-STAGE BUILD:
#    Combines Maven build and Docker build in one Dockerfile
#    WHY: Self-contained, no need for Maven on Jenkins
#
# 2. USE JRE INSTEAD OF JDK IN PRODUCTION:
#    FROM eclipse-temurin:17-jre-alpine
#    WHY: 50% smaller image, faster downloads, less attack surface
#
# 3. ADD NON-ROOT USER:
#    RUN addgroup -S spring && adduser -S spring -G spring
#    USER spring:spring
#    WHY: Security - don't run app as root, limits damage if compromised
#
# 4. ADD HEALTHCHECK:
#    HEALTHCHECK --interval=30s --timeout=3s \
#      CMD wget --quiet --tries=1 --spider http://localhost:8081/actuator/health || exit 1
#    WHY: Docker knows if app is healthy, can restart automatically
#    NOTE: Requires Spring Boot Actuator dependency
#
# 5. ADD LABELS FOR METADATA:
#    LABEL maintainer="your-email@example.com"
#    LABEL version="1.0"
#    LABEL description="Spring Boot Hello World Application"
#    WHY: Documentation, helps identify image purpose and owner
#
# 6. OPTIMIZE LAYER CACHING:
#    Copy pom.xml first, download dependencies, then copy source
#    WHY: Dependencies don't change often, Docker reuses cached layers
#
# 7. ADD JVM MEMORY LIMITS:
#    ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-Xmx512m", "-jar", "app.jar"]
#    WHY: Prevents OutOfMemoryError, respects container limits
#
# 8. ADD ENVIRONMENT VARIABLE SUPPORT:
#    ENV SPRING_PROFILES_ACTIVE=prod
#    WHY: Configure app behavior without rebuilding image
#
# ==============================================================================
# COMPLETE PRODUCTION-READY DOCKERFILE EXAMPLE:
# ==============================================================================
#
# # Build stage
# FROM maven:3.9-eclipse-temurin-17 AS build
# WORKDIR /app
# COPY pom.xml .
# RUN mvn dependency:go-offline
# COPY src ./src
# RUN mvn clean package -DskipTests
#
# # Runtime stage
# FROM eclipse-temurin:17-jre-alpine
#
# # Add non-root user
# RUN addgroup -S spring && adduser -S spring -G spring
#
# WORKDIR /app
#
# # Copy JAR from build stage
# COPY --from=build /app/target/*.jar app.jar
#
# # Add metadata
# LABEL maintainer="team@example.com"
# LABEL version="1.0"
#
# # Configure environment
# ENV SPRING_PROFILES_ACTIVE=prod
#
# # Expose port
# EXPOSE 8081
#
# # Add healthcheck
# HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
#   CMD wget --quiet --tries=1 --spider http://localhost:8081/actuator/health || exit 1
#
# # Run as non-root
# USER spring:spring
#
# # Start application with optimized JVM settings
# ENTRYPOINT ["java", \
#   "-XX:+UseContainerSupport", \
#   "-XX:MaxRAMPercentage=75.0", \
#   "-XX:+UseG1GC", \
#   "-jar", \
#   "app.jar"]
#
# ==============================================================================
# WHAT HAPPENS WITHOUT EACH COMPONENT:
# ==============================================================================
#
# NO FROM:
#   - Build fails immediately
#   - Error: "FROM instruction must be first"
#
# NO WORKDIR:
#   - Files copied to root directory (/)
#   - Messy, harder to debug, poor practice
#
# NO COPY:
#   - No application in container
#   - Container starts but Java error: "JAR file not found"
#
# NO EXPOSE:
#   - Container works fine, but no documentation
#   - Users don't know which port to map
#
# NO ENTRYPOINT/CMD:
#   - Container starts and immediately exits
#   - Application never runs
#
# USING CMD INSTEAD OF ENTRYPOINT:
#   - Works fine for simple cases
#   - Less strict, can be overridden with docker run arguments
#   - ENTRYPOINT is better for applications that must always run
#
# ==============================================================================
# IMAGE SIZE COMPARISON:
# ==============================================================================
#
# eclipse-temurin:17-jdk-alpine  ~330 MB
# eclipse-temurin:17-jre-alpine  ~170 MB (47% smaller)
# amazoncorretto:17-alpine       ~340 MB
# openjdk:17-alpine              ~340 MB
#
# RECOMMENDATION: Use JRE for production (smaller, faster, more secure)
#
# ==============================================================================
