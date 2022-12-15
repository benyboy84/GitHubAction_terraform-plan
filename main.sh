#!/bin/bash

# Optional inputs
if [[ ! "$INPUT_REFRESH" =~ ^(true|false)$ ]]; then
    echo "Terraform Plan | ERROR    | Unsupported command \"$INPUT_REFRESH\" for input \"Refresh\". Valid commands are \"true\", \"false\"."
    exit 1
else
    if [[ "$INPUT_REFRESH" == "true" ]]; then
        Refresh=""
    else
        Refresh="-refresh=false"
    fi
fi

Variables=""
if [[ -n "$INPUT_VARIABLE" ]]; then
    for Variable in $(echo "$INPUT_VARIABLE" | tr ',' '\n'); do
        Variables="$Variables -var $Variable"
    done
fi
echo $Variables

VarFiles=""
if [[ -n "$INPUT_VARIABLE_FILE" ]]; then
    for VariableFile in $(echo "$INPUT_VARIABLE_FILE" | tr ',' '\n'); do
        if [[ -f $VariableFile ]]; then
            VarFiles="$VarFiles -varfile=$VariableFile"
        else
            echo "Terraform Plan | ERROR    | Variable file \"$VariableFile\" does not exist."
            exit 1
        fi
    done
fi

Parallelism="10"
if [[ $INPUT_PARALLELISM -ge 0 && $INPUT_PARALLELISM -le 10 ]]; then
    Parallelism="-parallelism=$INPUT_PARALLELISM"
else
    echo "Terraform Plan | ERROR    | Unsupported command \"$INPUT_PARALLELISM\" for input \"Parallelism\". Valid commands are between 0-10."
    exit 1
fi

# Set arguments
Plan_Args="$Refresh $Variables $VarFiles $Parallelism"

# Gather the output of `terraform plan`.
echo "Terraform Plan | INFO     | Generates a terraform plan for $GITHUB_REPOSITORY."
Output=terraform plan -detailed-exitcode -input=false -no-color $Plan_Arg -out=${INPUT_OUT} 
ExitCode=${?}

echo "ExitCode=${ExitCode}" >> $GITHUB_OUTPUT

# Exit Code: 0, 2
# Meaning: 0 = Terraform plan succeeded with no changes. 2 = Terraform plan succeeded with changes.
# Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
if [[ $ExitCode -eq 0 || $ExitCode -eq 2 ]]; then
    Plan=$(terraform show -no-color ${INPUT_OUT})
    if echo "${Plan}" | egrep '^-{72}$' &> /dev/null; then
        Plan=$(echo "${Plan}" | sed -n -r '/-{72}/,/-{72}/{ /-{72}/d; p }')
        echo "egrep"
    fi
    Plan=$(echo "${Plan}" | tail -c 65300) # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
    Plan=$(echo "${Plan}" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
    Plan=$(echo "${Plan}" | sed -r 's/~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform plan Succeeded
<details><summary>Show Output</summary>
<p>

\`\`\`diff
$Plan
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
<p>
$Output
</p>
</details>"
fi

if [[ "$GITHUB_EVENT_NAME" != "push" && "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" && "$GITHUB_EVENT_NAME" != "pull_request_review_comment" && "$GITHUB_EVENT_NAME" != "pull_request_target" && "$GITHUB_EVENT_NAME" != "pull_request_review" ]]; then
 
    echo "Terraform Plan | WARNING  | $GITHUB_EVENT_NAME event does not relate to a pull request."

else

    # Look for an existing plan PR comment and delete
    echo "Terraform Plan | INFO     | Looking for an existing plan PR comment."

    Accept_Header="Accept: application/vnd.github.v3+json"
    Auth_Header="Authorization: token $INPUT_GITHUB_TOKEN"
    Content_Header="Content-Type: application/json"

    Pr_Comments_Url=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
    Pr_Comment_Uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

    Pr_Comment_Id=$(curl -sS -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comments_Url" | jq '.[] | select(.body|test ("### '"${GITHUB_WORKFLOW}"' - Terraform plan")) | .id')

    if [ "$Pr_Comment_Id" ]; then
        echo "Terraform Plan | INFO     | Found existing plan PR comment: $Pr_Comment_Id. Deleting."
        Pr_Comment_Url="$Pr_Comment_Uri/$Pr_Comment_Id"
        {
            curl -sS -X DELETE -H "$Auth_Header" -H "$Accept_Header" -L "$Pr_Comment_Url" > /dev/null
        } ||
        {
            echo "Terraform Plan | ERROR    | Unable to delete existing plan comment in PR."
        }
    else
        echo "Terraform Plan | INFO     | No existing plan PR comment found."
    fi
    
    # Add plan comment to PR.
    Pr_Payload=$(echo '{}' | jq --arg body "$Pr_Comment" '.body = $body')
    echo "Terraform Plan | INFO     | Adding plan comment to PR."
    {
        curl -sS -X POST -H "$Auth_Header" -H "$Accept_Header" -H "$Content_Header" -d "$Pr_Payload" -L "$Pr_Comments_Url" > /dev/null
    } ||
    {
        echo "Terraform Plan | ERROR    | Unable to add plan comment to PR."
    }

fi

if [[ $ExitCode -eq 1 ]]; then
    exit $ExitCode
else
    exit 0
fi
