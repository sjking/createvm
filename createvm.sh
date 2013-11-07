#! /bin/bash
# name: create_vm
# Create a virtual machine interactively using the CLI. There is an option to
# create a new vdi hdd, or to clone an existing one.
# Tested and works on Oracle VM VirtualBox Manager 4.1.12_Ubuntu

BASE_FOLDER="/media/vbox" # directory to hold VMs
HDD_SIZE=40000 # change this to suit your needs (size in MiB)
working_dir=`pwd`

# find the total memory of the machine
total_mem=`grep MemTotal /proc/meminfo | awk '{print $2a}' | awk '{print $1/1024}'`

# prompt for the name of the new vm
printf "Name of new Virtual Machine: "
read machine_name
printf "Enter how much memory to use in Mb [0-$total_mem Mb]: "
read memory_size

# prompt to use existing vdi drive or make a new one
while true; do
    read -p "Do you wish to clone an existing vdi hard drive? [Y/n] " yn
    case $yn in
        [Yy]* ) read -p "Enter path to existing vdi drive: " drive_path; break;;
        [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
    esac
done

echo "Creating new VM $machine_name in base folder $BASE_FOLDER..." 

# create the VM
VBoxManage createvm --name $machine_name --register --basefolder $BASE_FOLDER

# change into the base folder for this machine
machine_folder="$BASE_FOLDER/$machine_name"
cd $machine_folder 

vagrant=""

# prompt to use as a base box for vagrant (NAT), OR NOt (bridged nic)
# vagrant has to setup port forwarding for NAT to ssh from the host
while true; do
    read -p "Do you wish to use this VM as a base box for vagrant? [Y/n] " yn
    case $yn in
        [Yy]* ) 
            VBoxManage modifyvm $machine_name --memory $memory_size --acpi on --nic1 nat --natpf1 ssh,tcp,,2222,,22
            vagrant="true"
            break
            ;;
        [Nn]* ) 
            VBoxManage modifyvm $machine_name --memory $memory_size --acpi on --nic1 bridged --bridgeadapter1 eth0 --boot1 dvd
            break
            ;;
            * ) 
            echo "Please answer yes or no."
            ;;
    esac
done

# register the sata controller
VBoxManage storagectl $machine_name --add sata --name "Sata Controller"

# clone existing drive, or make a new one
hdd_name="$machine_name.vdi"
if [ -z "$drive_path" ]; then
    echo "Creating new vdi drive..."
    VBoxManage createhd --filename $hdd_name --size $HDD_SIZE
    read -p "Enter the path to an iso to install an OS: " iso_path
    if [ -n "$iso_path" ]; then
        [ -n "`echo $iso_path | egrep '^/.*$'`" ] || iso_path="$working_dir/$iso_path"
        echo "attaching iso file $iso_path" 
        VBoxManage storageattach $machine_name --storagectl "Sata Controller" \
            --port 1 --device 0 --type dvddrive --medium $iso_path
    fi
else
    [ -n "`echo $drive_path | egrep '^/.*$'`" ] || drive_path="$working_dir/$drive_path"
    echo "Using existing vdi drive from $drive_path..."
    # no need to attach and install iso for a cloned drive
    VBoxManage clonehd $drive_path $hdd_name
fi

VBoxManage storageattach $machine_name --storagectl "Sata Controller" --port 0 --device 0 --type hdd --medium $hdd_name

if [ -z "$vagrant" ]; then
    # keep a file of port numbers in the base directory, and increment them for new
    # vms
    last_port=`cat "$BASE_FOLDER/vrdeport" | tail -1 | awk '{print $2}'`
    if [ -z "$last_port" ]; then
        # prompt for a starting port, and create the file
        last_port="3000" # default
        read -p "Enter an uncommon port number for the VM [default 3001]: " input_port
        if [ -n "$input_port" ]; then
            last_port="$input_port"
        fi
        touch "$BASE_FOLDER/vrdeport"
    fi

    # increment last port and add it to the port file
    next_port=$(( $last_port + 1 ))
    echo "$machine_name $next_port" >> "$BASE_FOLDER/vrdeport"

    # assign that port number to this machine
    VBoxManage modifyvm $machine_name --vrdeport $next_port
    echo "VM \"$machine_name\" is assigned to port $next_port"
    # and set the vrde on
    VBoxManage controlvm $machine_name vrde on
fi

start=""

read -p "Do you want to start the new VM $machine_name? [Y/n]" yn
[ "$yn" = "y" ] || [ "$yn" = "Y" ] && start="true"

if [ -n "$start" ]; then
    if [ -n "$vagrant" ]; then
        VBoxManage startvm $machine_name
    else
        VBoxManage $startvm $machine_name -type headless && VBoxManage \
            controlvm $machine_name vrde on
    fi
fi
