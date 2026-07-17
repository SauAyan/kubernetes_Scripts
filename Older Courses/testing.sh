#!/bin/bash

# URL of the Nginx service
url="http://4.156.170.50/"

# Loop to make 10 requests
for i in {1..10}
do
    # Make request and extract the 'X-Pod-Name' header
    pod_name=$(curl -s -I $url | grep 'X-Pod-Name' | awk '{print $2}')
    
    # Print the pod name
    echo "Request $i responded by pod: $pod_name"
done
