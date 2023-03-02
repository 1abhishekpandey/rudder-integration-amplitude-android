#!/bin/bash
# Assuming user provides groupID and artifactID in DEPEDENCIES input
RELATIVE_PATH="amplitude/build.gradle"
LIBRARY="amplitude"

MULTIPLE_DEPENDENCIES_INPUT="com.moengage:moe-android-sdk,"
if [ -z "$MULTIPLE_DEPENDENCIES_INPUT" ]; then
    MULTIPLE_DEPENDENCIES_INPUT="com.amplitude:android-sdk,
    com.rudderstack.android.sdk:core,
    com.clevertap.android:clevertap-android-sdk,
    com.adobe.mobile:adobeMobileLibrary,
    com.appboy:android-sdk-ui,
    com.google.firebase:firebase-analytics,
    com.moengage:moe-android-sdk,
    com.appsflyer:af-android-sdk,
    com.singular.sdk:singular_sdk,
    com.fullstory:instrumentation-full,
    com.kochava.base:tracker,
    com.microsoft.appcenter:appcenter-analytics,
    com.optimizely.ab:android-sdk,
    com.bugsnag:bugsnag-android,
    com.leanplum:leanplum-core,
    io.intercom.android:intercom-sdk-base,
    io.branch.sdk.android:library,
    com.facebook.android:facebook-android-sdk,
    com.adjust.sdk:adjust-android,
    com.qualtrics:digital,
    com.comscore:android-analytics
    "
fi

if [ -z "$RELATIVE_PATH" ] || [ -z "$MULTIPLE_DEPENDENCIES_INPUT" ]; then
    echo "Mandatory fields must be present."
fi

# MULTIPLE_REPOSITORY_URLS="https://oss.sonatype.org/content/repositories/releases/, https://maven.google.com/, https://maven.singular.net/, https://maven.fullstory.com, https://s3-us-west-2.amazonaws.com/si-mobile-sdks/android/"

ALTERNATIVE_SDK="com.singular.sdk:singular_sdk"
ALTERNATIVE_URL="https://maven.singular.net/com/singular/sdk/singular_sdk/maven-metadata.xml"

function split_dependencies() {
    # Save the original IFS
    local original_ifs=$IFS
    # Set IFS to a comma
    IFS=","
    # Split the string into an array
    local dependencies=($1)
    # Reset the original IFS
    IFS=$original_ifs
    echo "${dependencies[@]}"
}

delimit_string() {
    local string=$1
    local delimiter=$2
    IFS=$delimiter read -ra str_array <<<"$string"
    echo "${str_array[@]}"
    IFS=$original_ifs
}

# Function to create a Maven dependency XML string
function create_dependency_xml() {
    groupID=${DELIMITED_DEPENDENCY[0]}
    artifactID=${DELIMITED_DEPENDENCY[1]}
    version=${DELIMITED_DEPENDENCY[2]}
    # Check if all three arguments are provided
    if [ -z "$groupID" ] || [ -z "$artifactID" ] || [ -z "$version" ]; then
        echo "false"
        exit 1
    fi

    # Build the XML string with the provided arguments
    DEPENDENCY_XML="\n\t\t<dependency>\n
    \t\t\t<groupId>${groupID}</groupId>\n
    \t\t\t<artifactId>${artifactID}</artifactId>\n
    \t\t\t<version>${version}</version>\n
    \t\t</dependency>"

    # Return the XML string
    echo $DEPENDENCY_XML
}

# Function to create a Repository XML string
function create_repository_xml() {
    urls=${REPOSITORY_URLS[@]}

    REPOSITORY_XML="<repositories>\n"
    count=1
    for url in ${urls[@]}; do
        id="id$count"
        REPOSITORY_XML+="\t\t<repository>\n
        \t\t\t<id>${id}</id>\n
        \t\t\t<url>${url}</url>\n
        \t\t</repository>\n"
        ((count++))
    done
    REPOSITORY_XML+="\t</repositories>\n\n"

    # Return the XML string
    echo $REPOSITORY_XML
}

REPOSITORY_URLS=($(split_dependencies "$MULTIPLE_REPOSITORY_URLS"))
# echo "Repository urls: ${REPOSITORY_URLS[@]}"
REPOSITORY_XML=$(create_repository_xml "${REPOSITORY_IDS[@]}" "${REPOSITORY_URLS[@]}")
# echo "Repository xml: $REPOSITORY_XML"

MULTIPLE_DEPENDENCIES=($(split_dependencies "$MULTIPLE_DEPENDENCIES_INPUT"))
# echo "Multiple dependencies:"

function get_individual_dependecy() {
    # Get the dependecy detail from the build.gradle file
    DEPENDENCY=$(grep "$individual_dependency" "$RELATIVE_PATH")

    # If dependency is enclosed in single quotes
    INDIVIDUAL_DEPENDENCY=$(echo "$DEPENDENCY" | sed -n "s/.*'\([^']*\)'.*/\1/p")
    # If dependency is enclosed in double quotes
    if [ -z "$INDIVIDUAL_DEPENDENCY" ]; then
        INDIVIDUAL_DEPENDENCY=$(echo "$DEPENDENCY" | sed -n 's/.*"\([^"]*\)".*/\1/p')
    fi

    echo "$INDIVIDUAL_DEPENDENCY"
}

# Fetch all the dependencies from gradle file
AGGREGATE_DEPENDENCIES=""
for individual_dependency in "${MULTIPLE_DEPENDENCIES[@]}"; do
    echo "Checking for: $individual_dependency"

    INDIVIDUAL_DEPENDENCY=($(get_individual_dependecy "$individual_dependency" "$RELATIVE_PATH"))
    echo "Individual dependency: $INDIVIDUAL_DEPENDENCY"
    delimiter=":"
    DELIMITED_DEPENDENCY=($(delimit_string "$INDIVIDUAL_DEPENDENCY" "$delimiter"))

    dependency_xml=$(create_dependency_xml "${DELIMITED_DEPENDENCY[@]}")

    # if [ -z "$INDIVIDUAL_DEPENDENCY" ]; then
    #     echo "OOPS"
    # fi
    # ./gradlew amplitude:dependencies

    if [ "$dependency_xml" != "false" ]; then
        AGGREGATE_DEPENDENCIES+="$dependency_xml"
    else
        if [ -n "$LIBRARY" ]; then
            echo "Finding version using 'gradlew <library>:dependencies command'"
            FIND_VERSION=$(./gradlew $LIBRARY:dependencies | grep -i ""$individual_dependency" -> " | cut -d ">" -f2 | sed 's/ //g' | sed -n '1p')
            echo "Found version: $FIND_VERSION"
            if [ -n "$FIND_VERSION" ]; then
                INDIVIDUAL_DEPENDENCY="$individual_dependency:$FIND_VERSION"
                echo "Individual dependency: $INDIVIDUAL_DEPENDENCY"
                delimiter=":"
                DELIMITED_DEPENDENCY=($(delimit_string "$INDIVIDUAL_DEPENDENCY" "$delimiter"))
                dependency_xml=$(create_dependency_xml "${DELIMITED_DEPENDENCY[@]}")
                AGGREGATE_DEPENDENCIES+="$dependency_xml"
            fi
        fi
    fi
done

create_pom_xml() {
    cat <<EOF >pom.xml
<?xml version="1.0" encoding="UTF-8"?>

<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.rudderstack.android.integration</groupId>
    <artifactId>amplitude</artifactId>
    <version>1.0.0</version>

    ${1}

    <dependencies>
        ${2}
    </dependencies>
</project>
EOF
}
# Create a pom.xml file
create_pom_xml "$REPOSITORY_XML" "$AGGREGATE_DEPENDENCIES"

# scans a project's dependencies and produces a report of those dependencies which have newer versions available
# NOTE: It'll not scan for deprecated dependency
OUTPUT=$(mvn versions:display-dependency-updates)
# OUTPUT=$(mvn versions:display-dependency-updates >/dev/null 2>&1)

echo "\n\n$OUTPUT\n\n"
NEWER_DEPENDENCIES=$(echo "$OUTPUT" | sed -n '/The following dependencies in Dependencies have newer versions:/,$p')
# echo "\n\n$NEWER_DEPENDENCIES \n\n"

function alternative_approach() {
    input_string=$(curl "$1")
    matching_string="<versioning>"
    # Using parameter expansion to extract the content after the matching string
    versioning="${input_string#*$matching_string}"
    # Search string
    search_string="<versions>"
    # Remove content after search string
    output=$(echo $versioning | sed "s/$search_string.*$//")
    version=$(echo $output | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | sed -n '1p')
    echo $version
}

# Initialize an empty body
body=()

extract_matching_line() {
    string="$1"
    search_string="$2"
    while read -r line; do
        if [[ "$line" == *"$search_string"* ]]; then
            echo "$line"
        fi
    done <<<"$string"
}

# Construct body
for individual_dependency in "${MULTIPLE_DEPENDENCIES[@]}"; do

    if [ "$individual_dependency" == "com.appboy:android-sdk-ui" ]; then
        echo "Newer dependency: $NEWER_DEPENDENCIES \n"
        match=$(extract_matching_line "$NEWER_DEPENDENCIES" "$individual_dependency")
        echo "Match: $match"
    fi

    # echo "Find individual dependency in the newer version list: $individual_dependency"
    OUTDATED_DEPENDENCY=$(echo "$NEWER_DEPENDENCIES" | grep -i "$individual_dependency")
    # OUTDATED_DEPENDENCY=$(echo "$NEWER_DEPENDENCIES" | awk -v search="$individual_dependency" '/search/{print}')
    # echo "Outdated dependency: $OUTDATED_DEPENDENCY"

    # Fetch current version
    INDIVIDUAL_DEPENDENCY=($(get_individual_dependecy "$individual_dependency" "$RELATIVE_PATH"))
    delimiter=":"
    DELIMITED_DEPENDENCY=($(delimit_string "$INDIVIDUAL_DEPENDENCY" "$delimiter"))
    CURRENT_VERSION=${DELIMITED_DEPENDENCY[2]}
    if [ -z "$CURRENT_VERSION" ]; then
        if [ -n "$LIBRARY" ]; then
            # echo "Finding version using 'gradlew <library>:dependencies command'"
            FIND_VERSION=$(./gradlew $LIBRARY:dependencies | grep -i ""$individual_dependency" -> " | cut -d ">" -f2 | sed 's/ //g' | sed -n '1p')
            # echo "Found version: $FIND_VERSION"
            if [ -n "$FIND_VERSION" ]; then
                INDIVIDUAL_DEPENDENCY="$individual_dependency:$FIND_VERSION"
                # echo "Individual dependency: $INDIVIDUAL_DEPENDENCY"
                delimiter=":"
                DELIMITED_DEPENDENCY=($(delimit_string "$INDIVIDUAL_DEPENDENCY" "$delimiter"))
                dependency_xml=$(create_dependency_xml "${DELIMITED_DEPENDENCY[@]}")
                CURRENT_VERSION="${DELIMITED_DEPENDENCY[2]}"
            fi
        fi
    fi
    # echo "Current version: $CURRENT_VERSION"

    LATEST_VERSION=""
    # Fetch Latest version using alternative approach
    if [ "$individual_dependency" == "$ALTERNATIVE_SDK" ] && [ -n "$ALTERNATIVE_URL" ]; then
        echo "Following alternative approach to fetch the url"
        LATEST_VERSION=($(alternative_approach "$ALTERNATIVE_URL"))
    fi
    if [ -z "$LATEST_VERSION" ]; then
        # Fetch latest version
        LATEST_VERSION=$(echo "$OUTDATED_DEPENDENCY" | cut -d ">" -f2 | sed 's/ //g' | sed -n '1p')
        # echo "Latest version: $LATEST_VERSION"
    fi
    if [ -n "$LATEST_VERSION" ]; then
        GENERATED_BODY="Update the "$individual_dependency" dependency from the current version $CURRENT_VERSION to the $LATEST_VERSION."
        # echo "$GENERATED_BODY"
        body+=("$GENERATED_BODY")
    fi
done

echo "Body:"
for body1 in "${body[@]}"; do
    echo "$body1"
done
#

#
# https://search.maven.org/#artifactdetails|com.google.firebase|firebase-analytics|19.0.2
# https://mvnrepository.com/artifact/com.google.firebase/firebase-analytics
# https://mvnrepository.com/artifact/com.google.firebase/firebase-analytics/maven-metadata.xml

# <!-- <repository>
# 			<id>central</id>
# 			<name>Maven Repository Switchboard</name>
# 			<url>https://search.maven.org</url>
# 		</repository> -->

#         <!-- <repository>
#             <id>Central</id>
#             <name>Maven Central Repository</name>
#             <url>https://repo1.maven.org/maven2/</url>
#         </repository> -->
