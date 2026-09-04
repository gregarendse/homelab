# # __generated__ by Terraform
# # Please review these resources and move them into your main configuration files.

# # __generated__ by Terraform from "qHbJv76uDYFuDcopk7yrBzwMhLMxF8TA"
# resource "auth0_client" "grafana" {
#   allowed_clients                                      = []
#   allowed_logout_urls                                  = []
#   allowed_origins                                      = []
#   app_type                                             = "regular_web"
#   async_approval_notification_channels                 = []
#   callbacks                                            = ["https://grafana.arendse.nom.za/login/generic_oauth"]
#   client_aliases                                       = []
#   client_metadata                                      = {}
#   compliance_level                                     = null
#   cross_origin_auth                                    = false
#   cross_origin_loc                                     = null
#   custom_login_page                                    = null
#   custom_login_page_on                                 = true
#   description                                          = null
#   encryption_key                                       = null
#   form_template                                        = null
#   grant_types                                          = ["authorization_code", "implicit", "refresh_token", "client_credentials"]
#   initiate_login_uri                                   = null
#   is_first_party                                       = true
#   is_token_endpoint_ip_header_trusted                  = false
#   logo_uri                                             = null
#   name                                                 = "Grafana"
#   oidc_conformant                                      = true
#   organization_discovery_methods                       = []
#   require_proof_of_possession                          = false
#   require_pushed_authorization_requests                = false
#   resource_server_identifier                           = null
#   skip_non_verifiable_callback_uri_confirmation_prompt = jsonencode(null)
#   sso                                                  = true
#   sso_disabled                                         = false
#   web_origins                                          = []
#   default_organization {
#     disable = true
#     flows   = []
#   }
#   jwt_configuration {
#     alg                 = "RS256"
#     lifetime_in_seconds = 36000
#     scopes              = {}
#     secret_encoded      = false
#   }
#   native_social_login {
#     apple {
#       enabled = false
#     }
#     facebook {
#       enabled = false
#     }
#     google {
#       enabled = false
#     }
#   }
#   refresh_token {
#     expiration_type              = "non-expiring"
#     idle_token_lifetime          = 2592000
#     infinite_idle_token_lifetime = true
#     infinite_token_lifetime      = true
#     leeway                       = 0
#     rotation_type                = "non-rotating"
#     token_lifetime               = 31557600
#   }
# }

# # __generated__ by Terraform from "r7n87ZX86czreuThfKgUsTs8r11YDoqg"
# resource "auth0_client" "default_app" {
#   allowed_clients                                      = []
#   allowed_logout_urls                                  = []
#   allowed_origins                                      = []
#   app_type                                             = null
#   async_approval_notification_channels                 = []
#   callbacks                                            = []
#   client_aliases                                       = []
#   client_metadata                                      = {}
#   compliance_level                                     = null
#   cross_origin_auth                                    = false
#   cross_origin_loc                                     = null
#   custom_login_page                                    = null
#   custom_login_page_on                                 = true
#   description                                          = null
#   encryption_key                                       = null
#   form_template                                        = null
#   grant_types                                          = ["authorization_code", "implicit", "refresh_token", "client_credentials"]
#   initiate_login_uri                                   = null
#   is_first_party                                       = true
#   is_token_endpoint_ip_header_trusted                  = false
#   logo_uri                                             = null
#   name                                                 = "Default App"
#   oidc_conformant                                      = true
#   organization_discovery_methods                       = []
#   require_proof_of_possession                          = false
#   require_pushed_authorization_requests                = false
#   resource_server_identifier                           = null
#   skip_non_verifiable_callback_uri_confirmation_prompt = jsonencode(null)
#   sso                                                  = false
#   sso_disabled                                         = false
#   web_origins                                          = []
#   default_organization {
#     disable = true
#     flows   = []
#   }
#   jwt_configuration {
#     alg                 = "RS256"
#     lifetime_in_seconds = 36000
#     scopes              = {}
#     secret_encoded      = false
#   }
#   refresh_token {
#     expiration_type              = "non-expiring"
#     idle_token_lifetime          = 1296000
#     infinite_idle_token_lifetime = true
#     infinite_token_lifetime      = true
#     leeway                       = 0
#     rotation_type                = "non-rotating"
#     token_lifetime               = 2592000
#   }
# }

# # __generated__ by Terraform from "PuJ7IKOvjEAKMJaQ8qp0CAQzNmOglYvJ"
# resource "auth0_client" "oauth2_proxy" {
#   allowed_clients                                      = []
#   allowed_logout_urls                                  = ["https://auth.arendse.nom.za"]
#   allowed_origins                                      = []
#   app_type                                             = "regular_web"
#   async_approval_notification_channels                 = []
#   callbacks                                            = ["https://auth.arendse.nom.za/oauth2/callback"]
#   client_aliases                                       = []
#   client_metadata                                      = {}
#   compliance_level                                     = null
#   cross_origin_auth                                    = false
#   cross_origin_loc                                     = null
#   custom_login_page                                    = null
#   custom_login_page_on                                 = true
#   description                                          = null
#   encryption_key                                       = null
#   form_template                                        = null
#   grant_types                                          = ["authorization_code", "implicit", "refresh_token", "client_credentials"]
#   initiate_login_uri                                   = null
#   is_first_party                                       = true
#   is_token_endpoint_ip_header_trusted                  = false
#   logo_uri                                             = null
#   name                                                 = "OAuth2 Proxy"
#   oidc_conformant                                      = true
#   organization_discovery_methods                       = []
#   require_proof_of_possession                          = false
#   require_pushed_authorization_requests                = false
#   resource_server_identifier                           = null
#   skip_non_verifiable_callback_uri_confirmation_prompt = jsonencode(null)
#   sso                                                  = true
#   sso_disabled                                         = false
#   web_origins                                          = []
#   default_organization {
#     disable = true
#     flows   = []
#   }
#   jwt_configuration {
#     alg                 = "RS256"
#     lifetime_in_seconds = 36000
#     scopes              = {}
#     secret_encoded      = false
#   }
#   native_social_login {
#     apple {
#       enabled = false
#     }
#     facebook {
#       enabled = false
#     }
#     google {
#       enabled = false
#     }
#   }
#   refresh_token {
#     expiration_type              = "non-expiring"
#     idle_token_lifetime          = 2592000
#     infinite_idle_token_lifetime = true
#     infinite_token_lifetime      = true
#     leeway                       = 0
#     rotation_type                = "non-rotating"
#     token_lifetime               = 31557600
#   }
# }

# # __generated__ by Terraform from "9uAWOXkl1OuFoL20xxOKh5KHiLoxzyVE"
# resource "auth0_client" "argocd_oci" {
#   allowed_clients                                      = []
#   allowed_logout_urls                                  = ["https://argocd.arendse.nom.za", "https://oci.argocd.arendse.nom.za"]
#   allowed_origins                                      = []
#   app_type                                             = "regular_web"
#   async_approval_notification_channels                 = []
#   callbacks                                            = ["https://argocd.arendse.nom.za/auth/callback", "https://oci.argocd.arendse.nom.za/auth/callback"]
#   client_aliases                                       = []
#   client_metadata                                      = {}
#   compliance_level                                     = null
#   cross_origin_auth                                    = false
#   cross_origin_loc                                     = null
#   custom_login_page                                    = null
#   custom_login_page_on                                 = true
#   description                                          = null
#   encryption_key                                       = null
#   form_template                                        = null
#   grant_types                                          = ["authorization_code", "implicit", "refresh_token", "client_credentials"]
#   initiate_login_uri                                   = null
#   is_first_party                                       = true
#   is_token_endpoint_ip_header_trusted                  = false
#   logo_uri                                             = null
#   name                                                 = "ArgoCD OCI"
#   oidc_conformant                                      = true
#   organization_discovery_methods                       = []
#   require_proof_of_possession                          = false
#   require_pushed_authorization_requests                = false
#   resource_server_identifier                           = null
#   skip_non_verifiable_callback_uri_confirmation_prompt = jsonencode(null)
#   sso                                                  = true
#   sso_disabled                                         = false
#   web_origins                                          = ["https://argocd.arendse.nom.za", "https://oci.argocd.arendse.nom.za"]
#   default_organization {
#     disable = true
#     flows   = []
#   }
#   jwt_configuration {
#     alg                 = "RS256"
#     lifetime_in_seconds = 36000
#     scopes              = {}
#     secret_encoded      = false
#   }
#   native_social_login {
#     apple {
#       enabled = false
#     }
#     facebook {
#       enabled = false
#     }
#     google {
#       enabled = false
#     }
#   }
#   refresh_token {
#     expiration_type              = "non-expiring"
#     idle_token_lifetime          = 2592000
#     infinite_idle_token_lifetime = true
#     infinite_token_lifetime      = true
#     leeway                       = 0
#     rotation_type                = "non-rotating"
#     token_lifetime               = 31557600
#   }
# }

# # __generated__ by Terraform from "yUhtOAKUT5TJdPQsGKmBmPqzMcmtoLmw"
# resource "auth0_client" "argocd_trinity" {
#   allowed_clients                                      = []
#   allowed_logout_urls                                  = []
#   allowed_origins                                      = []
#   app_type                                             = "regular_web"
#   async_approval_notification_channels                 = []
#   callbacks                                            = ["https://trinity.argocd.arendse.nom.za/auth/callback"]
#   client_aliases                                       = []
#   client_metadata                                      = {}
#   compliance_level                                     = null
#   cross_origin_auth                                    = false
#   cross_origin_loc                                     = null
#   custom_login_page                                    = null
#   custom_login_page_on                                 = true
#   description                                          = null
#   encryption_key                                       = null
#   form_template                                        = null
#   grant_types                                          = ["authorization_code", "implicit", "refresh_token", "client_credentials"]
#   initiate_login_uri                                   = null
#   is_first_party                                       = true
#   is_token_endpoint_ip_header_trusted                  = false
#   logo_uri                                             = null
#   name                                                 = "ArgoCD Trinity"
#   oidc_conformant                                      = true
#   organization_discovery_methods                       = []
#   require_proof_of_possession                          = false
#   require_pushed_authorization_requests                = false
#   resource_server_identifier                           = null
#   skip_non_verifiable_callback_uri_confirmation_prompt = jsonencode(null)
#   sso                                                  = true
#   sso_disabled                                         = false
#   web_origins                                          = []
#   default_organization {
#     disable = true
#     flows   = []
#   }
#   jwt_configuration {
#     alg                 = "RS256"
#     lifetime_in_seconds = 36000
#     scopes              = {}
#     secret_encoded      = false
#   }
#   native_social_login {
#     apple {
#       enabled = false
#     }
#     facebook {
#       enabled = false
#     }
#     google {
#       enabled = false
#     }
#   }
#   refresh_token {
#     expiration_type              = "non-expiring"
#     idle_token_lifetime          = 2592000
#     infinite_idle_token_lifetime = true
#     infinite_token_lifetime      = true
#     leeway                       = 0
#     rotation_type                = "non-rotating"
#     token_lifetime               = 31557600
#   }
# }
