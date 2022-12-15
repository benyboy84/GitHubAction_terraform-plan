# Terraform Plan action

This is one of a suite of terraform related actions.

This action uses the `terraform plan` to creates an execution plan, which lets you preview the changes that Terraform plans to make to your infrastructure.

If the triggering event relates to a PR, it will add a comment on the PR containing the generated plan.

## Outputs:
* `ExitCode`

  The options `-detailed-exitcode` returns a detailed exit code when the command exits. When provided, this argument changes the exit codes and their meanings to provide more granular information about what the resulting plan contains:
    0 = Succeeded with empty diff (no changes)
    1 = Error
    2 = Succeeded with non-empty diff (changes present)
    - Type: number

## Inputs

* `GitHub_Token`

  GitHub Token used to authenticate on behalf of GitHub Actions.. 

  - Type: string
  - Required

```yaml
        with:
          GitHub_Token: ${{ secrets.GITHUB_TOKEN }}
```

* `Refresh`

  Disables the default behavior of synchronizing the Terraform state with remote objects before checking for configuration changes. This can causes Terraform to ignore external changes, which could result in an incomplete or incorrect plan. Options: [true, false]

  - Type: boolean
  - Optional
  - Default: true

```yaml
        with:
          Refresh: [true, false]
```

* `Variable`

  Sets value for a single declared input variable. One per line. 
 
  - Type: string
  - Optional
  - Default: ''

```yaml
        with:
          Variable: |
            'NAME1=VALUE1'
            'NAME2=VALUE2'
```

* `Variable_File`

  Sets values for potentially many input variables declared in the configuration, using definitions from a "tfvars" file. 

  - Type: string
  - Optional
  - Default: ''  

```yaml
        with:
          Variable_File: |
            virtual_machine.tfvars
            storage.tfvars
```

* `Parallelism:`
    
  Limit the number of concurrent operations as Terraform walks the graph. Defaults to 10.
  - Type: integer
  - Optional
  - Default: 10    

```yaml
        with:
          Parallelism: 5
```

* `Out`

  Writes the generated plan to the given filename in an opaque file format that you can later use.
  - Type: string
  - Required
  - Default: terraform.tfplan

```yaml
        with:
          Out: terraform.tfplan
```

## Example usage

This example workflow runs on pull request and fails if terraform plan failed.

```yaml
name: Create an execution plan

on:
  pull_request:

jobs:
  TerraformPlan:
    runs-on: ubuntu-latest
    name: Create an execution plan
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: terraform init
        id: init
        run: terraform init

      - name: terraform plan
        id: plan
        uses: benyboy84/github-action-tf-plan@v1.0.0
        with:
          Github_Token: ${{ secrets.GITHUB_TOKEN }}
          Out_File: terraform.tfplan
```

## Screenshots

![plan](images/plan-output.png)
