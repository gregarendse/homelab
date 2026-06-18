
resource "tailscale_tailnet_key" "oracle" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 3600
  description   = "Oracle Cloud Instance Key"
}


data "cloudinit_config" "cloudinit" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    filename     = "userdata.yaml"
    content = templatefile("${path.module}/templates/userdata.yaml", {
      auth_key = tailscale_tailnet_key.oracle.key
    })
  }

}
