FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
ENV MAVEN_OPTS="-Xms32m -Xmx256m -XX:+UseSerialGC -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -XX:ActiveProcessorCount=2"
COPY server/pom.xml server/pom.xml
COPY server/src server/src
RUN --mount=type=cache,target=/root/.m2 mvn -B -f server/pom.xml -DskipTests package

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S workpanel && adduser -S -G workpanel workpanel
WORKDIR /app
COPY --from=build --chown=workpanel:workpanel /build/server/target/collaboration-server-1.0.0.jar app.jar
USER workpanel
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
