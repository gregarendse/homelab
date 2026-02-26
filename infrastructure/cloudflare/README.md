# Cloudflare Domain Terraform Project

This project configures a Cloudflare domain using Terraform, including DNS records and zone management. It's designed to work with a remote backend (Backblaze B2) and integrates with a network infrastructure project.

## Project Structure

- `main.tf`: Contains the main Cloudflare resources including DNS records and zone configuration
- `variables.tf`: Defines input variables for the Terraform configuration
- `data.tf`: Contains data sources for reading remote state from the network project
- `providers.tf`: Configures the Cloudflare provider and authentication
- `backend.tf`: Configures the remote backend for storing Terraform state
- `.auto.tfvars`: Contains variable values for this specific deployment
- `terraform.tfstate`: Local Terraform state file (backed up to remote backend)

## Prerequisites

- Terraform installed on your machine
- Cloudflare account with API token
- Access to Backblaze B2 bucket for remote state storage
- Network infrastructure already deployed (referenced in `data.tf`)

## Getting Started

### 1. Clone and Navigate

```bash
cd infrastructure/cloudflare
```

### 2. Configure Variables

Create or update the `.auto.tfvars` file with your specific values:

```hcl
# Required: Your Cloudflare API token
cloudflare_api_token = "your-cloudflare-api-token-here"

# Required: The domain name to manage
domain_name = "your-domain.com"

# S3 Backend Configuration (for remote state data sources)
# These values should match your .config.s3.tfbackend file
s3_backend_endpoint   = "https://s3.eu-central-003.backblazeb2.com"
s3_backend_region     = "eu-central-003"
s3_backend_access_key = "YOUR_BACKBLAZE_ACCESS_KEY"
s3_backend_secret_key = "YOUR_BACKBLAZE_SECRET_KEY"
s3_backend_bucket     = "BUCKET"
```

**Important Notes:**
- The `.auto.tfvars` file is automatically loaded by Terraform
- Keep your API token and S3 credentials secure and never commit them to version control
- A template file `.auto.tfvars.example` is provided for reference
- The `domain_name` should be a domain you own and have added to Cloudflare
- The S3 backend variables are used to access remote state from other projects (like the network infrastructure)

### 3. Cloudflare API Token Setup

1. Log into your Cloudflare account
2. Go to "My Profile" → "API Tokens"
3. Create a new token with the following permissions:
   - Zone:Zone:Read
   - Zone:DNS:Edit
   - Zone:Zone:Edit
4. Copy the token and add it to your `.auto.tfvars` file

### 4. Initialize Terraform

```bash
terraform init
```

This will:
- Download the Cloudflare provider
- Configure the remote backend connection to Backblaze B2
- Set up the workspace

### 5. Review the Plan

```bash
terraform plan
```

This will show you what resources will be created or modified. The current configuration will:
- Reference an existing Cloudflare zone for your domain
- Create an A record for `echo.your-domain.com` pointing to the public IP from the network infrastructure

### 6. Apply the Configuration

```bash
terraform apply
```

Review the proposed changes and type `yes` to confirm.

## Current Configuration

The project currently configures:
- **DNS Record**: `echo.{domain_name}` pointing to the public IP from the network infrastructure
- **Zone Management**: References an existing Cloudflare zone
- **Remote State**: Integrates with network infrastructure state for IP address resolution

## Backend Configuration

This project uses a remote backend stored in Backblaze B2:
- **Bucket**: `gregarendse-terraform`
- **Key**: `cloudflare/state.json`
- **Integration**: Reads from `network/state.json` for network infrastructure data

## Outputs

After deployment, you can view outputs with:
```bash
terraform output
```

## Cleanup

To remove all resources created by this project:
```bash
terraform destroy
```

**Warning**: This will delete the DNS records but will not remove the Cloudflare zone itself.

## Troubleshooting

### Common Issues

1. **API Token Errors**: Ensure your Cloudflare API token has the correct permissions
2. **Zone Not Found**: Make sure your domain is added to Cloudflare before running Terraform
3. **Backend Connection**: Verify your Backblaze B2 credentials and bucket access
4. **Network State**: Ensure the network infrastructure project has been deployed and state is available

### State Management

- State is stored remotely in Backblaze B2
- Local state files are backups only
- Use `terraform state` commands to inspect or modify state if needed

## Security Notes

- Never commit `.auto.tfvars` files containing sensitive data to version control
- Consider using environment variables for API tokens in production
- Regularly rotate your Cloudflare API tokens
- Review and audit the permissions granted to your API tokens