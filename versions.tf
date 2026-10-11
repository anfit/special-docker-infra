terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # State backend: none committed on purpose (account specific). Copy templates/backend.tf.example
  # to backend.tf and templates/backend.hcl.example to backend.hcl when you are ready for remote state.
}
