# Secrets

- **Storing:** `$DOF/bin/put-secret <app>/<name> --env ENV_NAME [--kms-key <key>]` reads the value from a hidden
  prompt, or from stdin when piped (`pbpaste | $DOF/bin/put-secret ...`). It never takes the value as an argument.
  It tags the secret `Project=devopsfoundry` and `App=<app>`, and prints the line for `app.tfvars`:

  ```hcl
  secrets = {
    STRIPE_KEY = "arn:aws:secretsmanager:us-east-1:111111111111:secret:myapp/stripe-AbCdEf"
  }
  ```

  Append `:json_key::` to an ARN to pass one field of a JSON secret.
- **Who types the value:** the person, or a pipe from where the value already is. Never you: a value you type
  lands in the conversation.
- **Checking:** `bin/deploy-app` checks every referenced secret exists, isn't being deleted and has a current
  version, with `describe-secret` only. Don't fetch a value to check it, and don't call `get-secret-value`.
- **Using one in a check:** a `VERIFY_SCRIPT` or a one-off check that needs a credential gets it at run time, for
  example with AWS's `asm-exec` and `{{resolve:secretsmanager:<id>:SecretString:<key>}}`, and must not print it.
- **Rotating:** the Redis auth token and SMTP password rotate with `$DOF/bin/rotate-secret --config <dir> redis|smtp`.
  App secrets you stored yourself rotate by storing a new value with `put-secret`, then redeploying.
- **Customer managed keys:** a secret under your own KMS key needs that key in `container-service`'s
  `secrets_kms_key_arns` (full-stack passes `kms_key_arn`), or tasks can't decrypt it.
