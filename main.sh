#!/bin/bash

# Optional inputs


# Gather the output of `terraform plan`.
echo "Terraform Plan | INFO  | Generates a terraform plan in $GITHUB_REPOSITORY."
Output=$(terraform plan -detailed-exitcode -input=false ${*} 2>&1)
ExitCode=${?}

# Exit Code: 0, 2
# Meaning: 0 = Terraform plan succeeded with no changes. 2 = Terraform plan succeeded with changes.
# Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 2 ]]; then
    Plan=$(echo "$Output" | sed -r '/^(An execution plan has been generated and is shown below.|Terraform used the selected providers to generate the following execution|No changes. Infrastructure is up-to-date.|No changes. Your infrastructure matches the configuration.|Note: Objects have changed outside of Terraform)$/,$!d') # Strip refresh section
    Plan=$(echo "$Plan" | sed -r '/Plan: /q') # Ignore everything after plan summary
    Plan=${Plan::65300} # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
    Plan=$(echo "$Plan" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
    Plan=$(echo "$CLEAN_PLAN" | sed -r 's/^~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform plan Succeeded
<details><summary>Show Output</summary>
\`\`\`diff
<p>

$Plan

</p>
\`\`\`
</details>"
fi

# Exit Code: 1
# Meaning: Terraform plan failed.
# Actions: Build PR comment.
if [[ $EXIT_CODE -eq 1 ]]; then
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
    Auth_Header="Authorization: token $GITHUB_TOKEN"
    Content_Header="Content-Type: application/json"

    Pr_Comments_Url=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
    Pr_Comment_Uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

    Pr_Comment_Id=$(curl -sS -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comments_Url" | jq '.[] | select(.body|test ("### Terraform plan Failed")) | .id')

    if [ "$Pr_Comment_Id" ]; then
        echo "Terraform Plan | INFO  | Found existing plan PR comment: $Pr_Comment_Id. Deleting."
        Pr_Comment_Url="$Pr_Comment_Uri/$Pr_Comment_Id"
        curl -sS -X DELETE -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comment_Url" > /dev/null
    else
        echo "Terraform Plan | INFO  | No existing plan PR comment found."
    fi
    
    # Add plan failure comment to PR.
    Pr_Payload=$(echo '{}' | jq --arg body "$Pr_Comment" '.body = $body')
    echo "Terraform Plan | INFO  | Adding plan failure comment to PR."
    curl -sS -X POST -H "$Auth_Header" -H "$Accept_Header" -H "$Content_Header" -d "$Pr_Payload" -L "$Pr_Comments_Url" > /dev/null

fi

exit $ExitCode