# Ansible: ServiceNow Agent
Il playbook ha lo scopo di installare e aggiornare l'agent servicenow sui sistemi Linux

## Puntamenti ad AWX 
project awx: https://ansible.telecomitalia.local/#/projects/1077/details

job template: https://ansible.telecomitalia.local/#/templates/job_template/1254/details
 

## Sistemi gestiti
Il playbook esegue l'installazione/aggiornamento dei seguenti sistemi linux:
- debian-8
- debian-9
- ubuntu-18.04
- RedHat-7
- RedHat-8
- RedHat-9
- centos-7
- centos-8
- sles-12
- sles-15


## Variabili di esecuzione del playbook

Il playbook contiene diverse variabili tra le quali le seguenti necessarie per l'esecuzione

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| reteNGDC | contesto di appartenenza del sistema | <code>Multiple Choice:  NGDC_SVIL_COLL,  NGDC_C1_C2_DMZEXT,  NGDC_C3,  SAG,  OLDDC_C1C2,  OLDDC_C3,  OLDDC_MATRIX,  DACON,  DOLMEN</code> | ✓ |  |
| AGENT_EXEC_TYPE | tipologia di esecuzione del playbook | <code>Multiple Choice: INSTALL, MONITORING_FILE_UPDATE, UPGRADE, ENABLE_AGENT</code> | ✓ |  |
| ACC_FORCE | forzare l'upgrade dell'agent | <code>Multiple Choice: yes, no</code> | ✓ |  |
| asset_label | asset label | <code>text</code> | ✓ |  |
| dry_run | test di installazione senza esecuzione effettiva | <code>boolean</code> | ✓ |  |
| mid_server_ip | ip del mid server | <code>text</code> | ✓ |  |


# ansible-master
