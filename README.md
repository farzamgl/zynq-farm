# zynq-farm
This repo is used to program and allocate jobs to the Zynq FPGA cluster connected to the AOI machine.

## NFS setup
In order to keep the work data in one place and avoid moving data back and forth between the server and FPGA clients, we use Network File System(NFS) to create an ethernet connection between a mounted directory on the server and its counterpart mounts on each FPGA board. This way we set up the work directory for each board directy from this repo.

After cloning this repo to setup its connection to the boards you need to add the folowing line to the `/etc/exports` file on the server:

	<absolute path to zynq-farm> 192.168.3.0/24(rw,sync,no_subtree_check,no_root_squash)

And you need to run the following commands to reflect the change in the filesystem:

	sudo exportfs -a
	sudo systemctl restart nfs-kernel-server

This setup only needs to be done once and doesn't need to be repeated unless you change the location of the zynq-farm directory. Also, you need `sudo` access for updating the `exports` file and restarting the NFS server, so if you're just a user, ask the server admin for help on the NFS setup.

## Getting started
### Allocating jobs
First, you need to statically allocate the benchmarks to each board in `Makefile.frag`. The boards are named by their local IP address. Currently we have 20 Ultra96v2 boards on the `192.168.3.80-99` address range. The board at `192.168.3.99` is reserved for CI so that leaves us with 19 boards at `192.168.3.80-98`. Finally, you should copy your NBF files to the `benchs` directory so the boards can access them for testing.

### Setting up the Makefile
Next, to make sure multiple users do not corrupt each others mountpoints on the boards, you need to update the `USER` variable in the Makefile to your name. So a mountpoint will be created at `/home/xilinx/$(USER)/mnt/nfs_client` for your work.

Next, you need to update `BRANCH` and `EXAMPLE` variables to the working zynq-parrot branch and example of your choosing.

Also, if you want to use a subset of the available FPGA boards you can update the `BOARDS` variable to an array of their addresses. For example:

	BOARDS = 192.168.3.80 192.168.3.81 192.168.3.82 192.168.3.83

Since everything is stored in the server, all the following Makefile targets are run on the server and there's no need to manually SSH into the FPGA boards for any of these steps.

### Mounting the boards
You can activate the NFS connection by running:

	make mount_boards

You only need to do this once unless the NFS connection is deactivated by resetting the boards or running:

	make unmount_boards

### Generating work directories
You can generate the work directories for each board by running:

	make gen_dirs

This will create the directories and clone and copy the zynq-parrot repo there so each board can independently use it's own instance of zynq-parrot. If you need to delete these directories you can run:

	make clean_dirs

### Loading the bitstream
Now you copy your zynq-parrot bistream to this repo and program the boards by running:

	make load_bitstreams BITSTREAM=<file>

If for any reason there are active SSH connections to the FPGA boards the command will fail with a message, and you need to resolve those connections before trying again.

### Running the benchmarks
Now you can start running the benchmarks using:

	make run_benchs

This will create background SSH jobs to each board and doesn't block the command-line. To monitor the progress of each board you can look at the simulation logs at `192.168.3.x/<benchmark>.run.log`. You can also monitor the pending jobs using:

	make query_ssh

### Rebooting the boards
The Ultra96v2 boards are configured to automatically reboot if their ARM core hangs for 60 seconds, so in monst cases there's no need to manually reboot the cluster. But if a reboot is necessary you can run the following command and wait for the cluster to come back online:

	make reboot_boards

### Local FPGA run
If you don't need to start jobs from the server and want to run a single benchmark on a board, after generating and mounting the directory, you can always manually SSH into the board and `cd` into the `/home/xilinx/<USER>/mnt/nfs_client/<IP>/zynq-parrot` directory and manually program and run the program from that repo.

## Adding Zynq boards to the cluster
To add another Pynq-Z2 or Ultra96v2 board to the existing cluster you need to first assign it an static IP on the `192.168.3.2-99` range that's not currently in use in the cluster. Also the `nfs-common` package needs to be installed on the board for NFS connection. To query currently online boards on the cluster run:

	make ping_boards

## NBF generation
For instructions on how to build NBF files visit the `Makefile` and `README` at `zynq-parrot/software`.
