{  
  "type": "cronjob",  
  "apiVersion": "batch/v1beta1",  
  "metadata": {  
    "name": "bountybeacon",  
    "namespace": "bountybeacon"  
  },  
  "spec": {  
    "schedule": "0 3 * * 1",  
    "jobTemplate": {  
      "spec": {  
        "template": {  
          "spec": {  
            "containers": [  
              {  
                "name": "bountybeacon",  
                "image": "gregarendse/bountybeacon:latest",  
                "envFrom": [  
                  {  
                    "secretRef": {  
                      "name": "bountybeacon-secrets"  
                    }  
                  }  
                ]  
              }  
            ],  
            "restartPolicy": "OnFailure"  
          }  
        }  
      }  
    }  
  }
}