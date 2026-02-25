#!/bin/sh
# Gradle wrapper script
# Generated for Imlac PDS-1 project

##############################################################################
##
##  Gradle start up script for UN*X
##
##############################################################################

# Attempt to set APP_HOME
PRG="$0"
while [ -h "$PRG" ] ; do
    ls=`ls -ld "$PRG"`
    link=`expr "$ls" : '.*-> \(.*\)$'`
    if expr "$link" : '/.*' > /dev/null; then
        PRG="$link"
    else
        PRG=`dirname "$PRG"`"/$link"
    fi
done
APP_HOME=`dirname "$PRG"`

APP_NAME="Gradle"
APP_BASE_NAME=`basename "$0"`

# Add default JVM options here
DEFAULT_JVM_OPTS='"-Xmx64m" "-Xms64m"'

# Use JAVA_HOME if set
if [ -n "$JAVA_HOME" ] ; then
    JAVACMD="$JAVA_HOME/bin/java"
else
    JAVACMD="java"
fi

exec "$JAVACMD" $DEFAULT_JVM_OPTS \
  -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" \
  org.gradle.wrapper.GradleWrapperMain "$@"
