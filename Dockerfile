FROM openjdk:8-jre-slim as build_release
LABEL maintainer="ArchivesSpaceHome@lyrasis.org"

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get -y install --no-install-recommends git wget unzip build-essential

COPY . /source

RUN cd /source && \
    export ARCHIVESSPACE_VERSION=${SOURCE_BRANCH:-`git symbolic-ref -q --short HEAD || git describe --tags --match v*`} && \
    echo "Using version: $ARCHIVESSPACE_VERSION" && \
    ./scripts/build_release $ARCHIVESSPACE_VERSION && \
    mv ./*.zip / && \
    cd / && \
    unzip /*.zip -d / && \
    wget http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar && \
    cp /mysql-connector-java-5.1.39.jar /archivesspace/lib/

ADD docker-startup.sh /archivesspace/startup.sh
RUN chmod u+x /archivesspace/startup.sh

FROM openjdk:8-jre-slim

ENV ARCHIVESSPACE_LOGS=/dev/null \
    LANG=C.UTF-8

COPY --from=build_release /archivesspace /archivesspace

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get -y install --no-install-recommends ca-certificates wget unzip && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 1000 archivesspace && \
    useradd -l -M -u 1000 -g archivesspace archivesspace && \
    chown -R archivesspace:archivesspace /archivesspace

USER archivesspace

EXPOSE 8080 8081 8089 8090 8092

HEALTHCHECK --interval=1m --timeout=5s --start-period=5m --retries=2 \
  CMD wget -q --spider http://localhost:8089/ || exit 1

CMD ["/archivesspace/startup.sh"]
