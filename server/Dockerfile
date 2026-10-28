# 서버 이미지. 빌드: docker buildx build --platform linux/arm64 -t remine-server server
# 1단계(빌드)는 빌드하는 기계의 아키텍처($BUILDPLATFORM)에서 돈다. jar는 아키텍처와 무관해서
# x86 러너가 arm64 이미지를 만들 때 Gradle을 QEMU 에뮬레이션으로 돌리지 않아도 된다.
# 테스트는 CI의 별도 단계(./gradlew test)에서 돌리고 여기서는 jar만 만든다.
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk AS build
WORKDIR /src
# 의존성 다운로드를 소스와 다른 층에 둬서, 소스만 바뀌면 이 층은 캐시를 쓴다.
COPY gradlew settings.gradle build.gradle gradle.properties ./
COPY gradle gradle
RUN ./gradlew dependencies --no-daemon -q > /dev/null
COPY src src
RUN ./gradlew bootJar --no-daemon -q \
 && cp "$(find build/libs -name '*.jar' ! -name '*-plain.jar')" /src/app.jar

# 2단계(실행)는 대상 아키텍처(arm64) 이미지. RUN이 없어 에뮬레이션 없이 만들어진다.
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build --chown=10001:10001 /src/app.jar app.jar
# root가 아닌 사용자로 실행한다(계정 생성 RUN 없이 숫자 uid만 지정).
USER 10001
EXPOSE 8080
# 메모리: 힙을 컨테이너 한도(compose mem_limit)의 60%로 잡고 나머지는 메타스페이스·스레드 스택·버퍼에 남긴다.
# 1GB 인스턴스라 GC는 오버헤드가 가장 작은 Serial, OOM이면 멈춰 있지 말고 종료해 compose가 다시 띄우게 한다.
# 추가 옵션은 JAVA_TOOL_OPTIONS 환경변수로 넣는다.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=60", "-XX:+UseSerialGC", "-Xss512k", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
