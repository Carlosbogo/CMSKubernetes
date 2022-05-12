#!/bin/bash
# helper script to deploy given service with given tag to k8s infrastructure

if [ $# -ne 3 ]; then
    echo "Usage: deploy-secrets.sh <namespace> <service-name> <path_to_configuration>"
    exit 1
fi

cluster_name=`kubectl config get-clusters | grep -v NAME`

ns=$1
srv=$2
conf=$3
tmpDir=/tmp/$USER/sops
if [ -d $tmpDir ]; then
   rm -rf $tmpDir
fi
mkdir -p $tmpDir
cd $tmpDir


if [ -z "`command -v sops`" ]; then
  # download soap in tmp area
  wget -O sops https://github.com/mozilla/sops/releases/download/v3.7.2/sops-v3.7.2.linux.amd64
  chmod u+x sops
  mkdir -p $HOME/bin
  echo "Download and install sops under $HOME/bin"
  cp ./sops $HOME/bin
fi
    # cmsweb configuration area
    echo "+++ cluster name: $cluster_name"
    echo "+++ configuration: $conf"
    echo "+++ cms service : $srv"
    echo "+++ namespaces   : $ns"
    echo "+++ secretref   : $secretref"

    if [ ! -d $conf/$srv ]; then
	echo "Unable to locate $conf/$srv, please provide proper directory structure like <configuration>/<service>/<files>"
  	exit 1
    fi
   
    # Get SOPS decryption key (if it's not there) and set it as the default decryption file
    sopskey=$SOPS_AGE_KEY_FILE
    kubectl get secrets $ns-keys-secrets -n $ns --template="{{index .data \"$ns-keys.txt\" | base64decode}}" > "$tmpDir/$ns-keys.txt"
    export SOPS_AGE_KEY_FILE="$tmpDir/$ns-keys.txt"
    echo "Key file: $SOPS_AGE_KEY_FILE"

    # check (and copy if necessary) hostkey/hostcert.pem files in configuration area of frontend

    if [ "$srv" == "frontend" ] ; then

	if [ ! -f $conf/frontend/hostkey.pem ]; then
        	cp $cmsweb_key $conf/frontend/hostkey.pem
	fi
	
	if [ ! -f $conf/frontend/hostcert.pem ]; then
        	cp $cmsweb_crt $conf/frontend/hostcert.pem
	fi
    fi

    if [ "$srv" == "frontend-ds" ] ; then

	if [ ! -f $conf/frontend-ds/hostkey.pem ]; then
        	cp $cmsweb_key $conf/frontend-ds/hostkey.pem
	fi
    	if [ ! -f $conf/frontend-ds/hostcert.pem ]; then
        	cp $cmsweb_crt $conf/frontend-ds/hostcert.pem
    	fi
    fi
	secretdir=$conf/$srv
        # the underscrore is not allowed in secret names
        osrv=$srv
        srv=`echo $srv | sed -e "s,_,,g"`
        files=""

### Substitution for APS/XPS/SPS client secrets in config.json      

    if [ "$srv" == "auth-proxy-server" ] || [ "$srv" == "x509-proxy-server" ] || [ "$srv" == "scitokens-proxy-server" ] ; then
       for fname in $secretdir/*; do
         if [[ $fname == *.encrypted ]]; then
	    sops -d $fname > $secretdir/$(basename $fname .encrypted)
         fi
       done
       if [ -d $secretdir ] && [ -n "`ls $secretdir`" ] && [ -f $secretdir/client.secrets ]; then
           export CLIENT_SECRET=`grep CLIENT_SECRET $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           export CLIENT_ID=`grep CLIENT_ID $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           export IAM_CLIENT_ID=`grep IAM_CLIENT_ID $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           export IAM_CLIENT_SECRET=`grep IAM_CLIENT_SECRET $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           export COUCHDB_USER=`grep COUCHDB_USER $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           export COUCHDB_PASSWORD=`grep COUCHDB_PASSWORD $secretdir/client.secrets | head -n1 | awk '{print $2}'`
           if [ -f $secretdir/config.json ]; then
              if [ -n "${IAM_CLIENT_ID}" ]; then
                 sed -i -e "s,IAM_CLIENT_ID,$IAM_CLIENT_ID,g" $secretdir/config.json
              fi
              if [ -n "${IAM_CLIENT_SECRET}" ]; then
                 sed -i -e "s,IAM_CLIENT_SECRET,$IAM_CLIENT_SECRET,g" $secretdir/config.json
              fi
              if [ -n "${CLIENT_ID}" ]; then
                 sed -i -e "s,CLIENT_ID,$CLIENT_ID,g" $secretdir/config.json
              fi
              if [ -n "${CLIENT_SECRET}" ]; then
                 sed -i -e "s,CLIENT_SECRET,$CLIENT_SECRET,g" $secretdir/config.json
              fi
              if [ -n "${COUCHDB_USER}" ]; then
                 sed -i -e "s,COUCHDB_USER,$COUCHDB_USER,g" $secretdir/config.json
              fi
              if [ -n "${COUCHDB_PASSWORD}" ]; then
                 sed -i -e "s,COUCHDB_PASSWORD,$COUCHDB_PASSWORD,g" $secretdir/config.json
              fi
          fi
       fi
    fi 
        if [ -d $secretdir ] && [ -n "`ls $secretdir`" ]; then
        	for fname in $secretdir/*; do
           	  if [[ $fname == *.encrypted ]]; then
	       	    sops -d $fname > $secretdir/$(basename $fname .encrypted)
	            fname=$secretdir/$(basename $fname .encrypted)
		    echo "Decrypted file $fname"
                  fi
		  if [[ ! $files == *$fname* ]]; then
                    files="$files --from-file=$fname"
		  fi
                done
        fi

        if [ "$ns" == "dbs" ]; then
		for fname in $conf/dbs/*; do
                  if [[ $fname == *.encrypted ]]; then
                    sops -d $fname > $conf/dbs/$(basename $fname .encrypted)
                  fi
                done
        	if [ -f $conf/dbs/DBSSecrets.py ]; then
                        files="$files --from-file=$conf/dbs/DBSSecrets.py"
                fi
                if [ -f $conf/dbs/NATSSecrets.py ]; then
                        files="$files --from-file=$conf/dbs/NATSSecrets.py"
                fi
        fi

        kubectl create secret generic ${srv}-secrets \
                $files --dry-run=client -o yaml | \
                kubectl apply --namespace=$ns -f -
    export SOPS_AGE_KEY_FILE=$sopskey
    echo
    echo "+++ list secrets"
    kubectl get secrets -n $ns
    rm -rf $tmpDir

