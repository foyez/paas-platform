terraform {
  required_version = ">= 1.5.7"

  backend "s3" {
    bucket         = "terraform-state-700935105905-eu-central-1"
    key            = "paas-platform/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = { source = "hashicorp/tls" }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "paas-platform"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# Get the list for available AZs in the region
data "aws_availability_zones" "azs" {
  state = "available"
}