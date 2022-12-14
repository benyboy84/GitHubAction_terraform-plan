#!/bin/bash

# Gather the output of `terraform plan`.
echo "Terraform Plan | INFO  | Generates a terraform plan for $GITHUB_REPOSITORY."
if [[ -n "$INPUT_OUT_FILE" ]]; then
    
    terraform plan -detailed-exitcode -input=false -no-color -out=${INPUT_OUT_FILE} > /dev/null
    ExitCode=${?}
    Output=$(terraform show -no-color ${INPUT_OUT_FILE})

else

    Output=$(terraform plan -detailed-exitcode -input=false -no-color ${*} 2>&1)
    ExitCode=${?}

fi

echo "ExitCode=${ExitCode}" >> $GITHUB_OUTPUT

# Exit Code: 0, 2
# Meaning: 0 = Terraform plan succeeded with no changes. 2 = Terraform plan succeeded with changes.
# Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
if [[ $ExitCode -eq 0 || $ExitCode -eq 2 ]]; then
    Output=$(echo "${Output}" | sed -n '/Terraform will perform the following actions/,$p') # Ignore everything before 
    if echo "${Output}" | egrep '^-{72}$' &> /dev/null; then
        Output=$(echo "${Output}" | sed -n -r '/-{72}/,/-{72}/{ /-{72}/d; p }')
        echo "egrep"
    fi
    Output=$(echo "${Output}" | tail -c 65300) # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
    Output=$(echo "${Output}" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
    Output=$(echo "${Output}" | sed -r 's/~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform plan Succeeded
<details><summary>Show Output</summary>
<p>

\`\`\`diff
$Output
\`\`\`

</p>
</details>"
fi

# Exit Code: 1
# Meaning: Terraform plan failed.
# Actions: Build PR comment.
if [[ $ExitCode -eq 1 ]]; then
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform plan Failed
<details><summary>Show Output</summary>
\`\`\`
<p>
$Output
</p>
\`\`\`
</details>"
fi

if [[ "$GITHUB_EVENT_NAME" == "pull_request"  ]]; then
     # Look for an existing plan PR comment and delete
    echo "Terraform Plan | INFO  | Looking for an existing plan PR comment."

    Accept_Header="Accept: application/vnd.github.v3+json"
    Auth_Header="Authorization: token $INPUT_GITHUB_TOKEN"
    Content_Header="Content-Type: application/json"

    Pr_Comments_Url=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
    Pr_Comment_Uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

    Pr_Comment_Id=$(curl -sS -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comments_Url" | jq '.[] | select(.body|test ("### '"${GITHUB_WORKFLOW}"' - Terraform plan")) | .id')

    if [ "$Pr_Comment_Id" ]; then
        echo "Terraform Plan | INFO  | Found existing plan PR comment: $Pr_Comment_Id. Deleting."
        Pr_Comment_Url="$Pr_Comment_Uri/$Pr_Comment_Id"
        curl -sS -X DELETE -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comment_Url" > /dev/null
    else
        echo "Terraform Plan | INFO  | No existing plan PR comment found."
    fi
    
    # Add plan comment to PR.
    Pr_Payload=$(echo '{}' | jq --arg body "$Pr_Comment" '.body = $body')
    echo "Terraform Plan | INFO  | Adding plan comment to PR."
    curl -sS -X POST -H "$Auth_Header" -H "$Accept_Header" -H "$Content_Header" -d "$Pr_Payload" -L "$Pr_Comments_Url" > /dev/null

fi

if [[ $ExitCode -eq 1 ]]; then
    exit $ExitCode
else
    exit 0
fi
