Agent role
=========

This role has the following tasks:
- configure the VM
- install the servicenow agent
- configure the certificate

Requirements
------------



Role Variables
--------------

A description of the settable variables for this role. Each var has a default value

name | description | default 
--- | --- | --- 
dry_run | run in check mode without any effective change | false 
debug_mode | print debug messages | true 
enable_check | enable check environment | true
enable_tag | enable task in tag.yml | true
enable_connection | enable task in connection_check.yml |  true
enable_script | enable task in installation_script.yml | true
enable_certs | enable task for the certificate configuration | true
tag_path | the path of the tag file | /opt/HP/Discovery/etichetta.txt
tag | the effective tag to insert  | tag: 123456789
file_owner | owner of the tag file | "ccansible"
file_group | group of the tag file | "ccansible"
file_perm | permission of the tag file | '0644'
mid_server_ip | ip address of the mid server | "10.58.236.83"
mid_server_port | port to the mid server | "8443"
script_path | path to the agent installation script | "agent-role/files/script/install_linux.bash"
execution_path | running path of the installation script | "/tmp/install_linux.bash"
acc_svc | name of the service installed by the script | "acc"
src_cert_path | source path of the certificate | "agent-role/files/certs/labcacert.pem"
dest_cert_path | destination path of the certificate | "/etc/pki/ca-trust/source/anchors/"
skip_tls_verify | parameter to modify | "insecure-skip-tls-verify | | false"
agent_coll_file_path | servicenow config file | "/etc/servicenow/agent-client-collector/acc.yml"
agent_coll_log_path | sservicenow log file | "/var/log/servicenow/agent-client-collector/acc.log"
agent_coll_check_string | string of connection | "successfully connected"
reteNGDC | environment variable |"NGDC_SVIL_COLL"
rmt_src | define the source of the agent cert/key: yes if the files are on the managed host; no if the files are on the master |"no"
dest_agent_cert_path | agent certificate destination path  |"/home/centos/acc01.cert"
dest_agent_key_path | agent key destination path |"/home/centos/acc01.key"


Dependencies
------------



Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - name: "Importing Installation role"
      import_role:
        name: agent-role

License
-------

BSD

Author Information
------------------

