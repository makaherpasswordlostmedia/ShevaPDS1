#!/bin/sh
# Gradle wrapper script

# Find project root (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find java
if [ -n "$JAVA_HOME" ]; then
    JAVA="$JAVA_HOME/bin/java"
else
    JAVA="java"
fi

# Wrapper jar
WRAPPER_JAR="$SCRIPT_DIR/gradle/wrapper/gradle-wrapper.jar"

# Launch — note: NO variable expansion for JVM opts, list them directly
exec "$JAVA" \
    -Xmx512m \
    -Xms64m \
    -Dfile.encoding=UTF-8 \
    "-Dorg.gradle.appname=gradlew" \
    -classpath "$WRAPPER_JAR" \
    org.gradle.wrapper.GradleWrapperMain \
    "$@"
