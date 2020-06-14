# Ubuntu Landscape Server (for Docker)
  
A work-in-progress Ubuntu Landscape Server for use with Docker.
  
Designed to be an "all-in-one" solution. For majority of sys-admins this is probably not ideal and should instead consider the [https://docs.ubuntu.com/landscape/en/landscape-install-juju](juju Deployment method).

Uses [https://acme.me](acme.me) to retrieve [https://letsencrypt.org](Let'sEncrypt) certificate.

## Env Variables

### Acme.sh

To use DNS-based verification, use one of the following pairs of variables. Webroot verification will be used as a fall-back if no variables are used.  
  
For Cloudflare:  
CF_Email=""  
CF_Key=""  
or  
CF_Account_ID=""  
CF_Token=""  
  
For AWS (Route53):  
AWS_ACCESS_KEY_ID  
AWS_SECRET_ACCESS_KEY  
  
For FreeDNS:  
FREEDNS_User  
FREEDNS_Password  
  
Certificates can be either RSA or ECDSA, based on the following variable. Use "false" for RSA and "true" for ECDSA (default is true)  
ECDSA=true  
  
Enter the FQDN (Domain) that will be used (eg. landscape.mydomain.com).  Required.  
DOMAIN=""  
