#### Initialize Docker Swarm on a machine ---->

##### docker swarm init --advertise-addr <IP address and port of machine that acts as cluster lead node> --listen-addr <IP address and port of machine that listens to the swarm traffic>
Eg. docker swarm init --advertise-addr 172.25.208.1:2377 --listen-addr 172.25.208.1:2377

1. docker swarm init: tells Docker to initialize a new swarm and make this node the firstmanager. 
It also enables swarm mode on the node.
2. --advertise-addr: is the IP and port that other nodes should use to connect to thismanager. It’s an optional flag, but it 
gives you control over which IP gets used on nodeswith multiple IPs. "Use this address to contact me."
3. --listen-addr: lets you specify which IP and port you want to listen on for swarm traffic.
This will usually match the --advertise-addr. "Bind the Swarm manager API to this exact local address."

#### Output:
Swarm initialized: current node (g66g17cu6rn4aibs93b7bhgz4) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-40cdr8tejhvenvfimx5882xfa575cf83vgnthjre8m56vmetev-94x7tcyvdsjvb2q7m3fxi9d1z 192.168.65.3:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

#### docker node ls
To check all nodes in the docker swarm created.

#### Add Managers and Workers
This uses the generated token

##### docker swarm join-token manager ----> <TOKEN_TO_JOIN_AS_MANAGER>
gets a token to allow another machine to join as manager to this swarm

##### docker swarm join-token  worker -----> <TOKEN_TO_JOIN_AS_WORKER>
gets a token to allow another machine to join as worker to this swarm

To add machines as managers and workers use the tokens generated
##### docker swarm join --token <TOKEN_TO_JOIN_AS_MANAGER> <MANAGER_ADDRESS>:2377
##### docker swarm join --token <TOKEN_TO_JOIN_AS_WORKER> <WORKER_ADDRESS>:2377

#### Delete Swarm
##### docker swarm leave --force
