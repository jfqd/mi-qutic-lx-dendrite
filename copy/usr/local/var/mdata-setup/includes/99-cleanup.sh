#!/usr/bin/bash

mdata-delete mail_smarthost || true
mdata-delete mail_auth_user || true
mdata-delete mail_auth_pass || true
mdata-delete mail_adminaddr || true

mdata-delete dendrite_password || true
mdata-delete dendrite_backup_pwd || true
