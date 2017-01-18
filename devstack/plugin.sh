# Devicedemo devstack plugin
# Install and start **Devicedemo** service
# To enable a minimal set of Devicedemo services:
# - add the following to the [[local|localrc]] section in the local.conf file:
#   # enable Devicedemo
#   enable_plugin devices https://github.com/yumaojun03/devices.git
#   enable_service devices-api
#
# stack.sh
# ---------
# install_devices
# install_python_devicesclient
# configure_devices
# init_devices
# start_devices
# stop_devices
# cleanup_devices


# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace


# Support potential entry-points console scripts in VENV or not
if [[ ${USE_VENV} = True ]]; then
    PROJECT_VENV["devices"]=${DEVICEDEMO_DIR}.venv
    DEVICEDEMO_BIN_DIR=${PROJECT_VENV["devices"]}/bin
else
    DEVICEDEMO_BIN_DIR=$(get_python_exec_prefix)
fi


# Functions
# ---------

# Activities to do before devices has been installed.
function preinstall_devices {
    echo_summary "Preinstall not in virtualenv context. Skipping."
}

# # install_python_devicesclient() - Collect source and prepare
# function install_python_devicesclient {
#     # Install from git since we don't have a release (yet)
#     echo_summary "Install Devicedemo Client"
#     git_clone_by_name "python-devicesclient"
#     setup_dev_lib "python-devicesclient"
# }

# install_devices() - Collect source and prepare
function install_devices {
    # install_python_devicesclient
    setup_develop $DEVICEDEMO_DIR
    sudo install -d -o $STACK_USER -m 755 $DEVICEDEMO_CONF_DIR
}

# configure_devices() - Set config files, create data dirs, etc
function configure_devices {
    cp $DEVICEDEMO_DIR$DEVICEDEMO_CONF_DIR/policy.json $DEVICEDEMO_CONF_DIR
    cp $DEVICEDEMO_DIR$DEVICEDEMO_CONF_DIR/api_paste.ini $DEVICEDEMO_CONF_DIR

    # default
    iniset_rpc_backend devices $DEVICEDEMO_CONF DEFAULT
    iniset $DEVICEDEMO_CONF DEFAULT notification_topics 'notifications'
    iniset $DEVICEDEMO_CONF DEFAULT debug "$ENABLE_DEBUG_LOG_LEVEL"

    # database
    iniset $DEVICEDEMO_CONF database connection `database_connection_url devices`

    # keystone middleware
    configure_auth_token_middleware $DEVICEDEMO_CONF devices $DEVICEDEMO_AUTH_CACHE_DIR
}

# Create devices related accounts in Keystone
function create_devices_accounts {
    if is_service_enabled devices-api; then

        create_service_user "devices" "admin"

        local devices_service=$(get_or_create_service "devices" \
            "device" "OpenStack Device Service")

        get_or_create_endpoint $devices_service \
            "$REGION_NAME" \
            "$DEVICEDEMO_SERVICE_PROTOCOL://$DEVICEDEMO_SERVICE_HOST:$DEVICEDEMO_SERVICE_PORT/" \
            "$DEVICEDEMO_SERVICE_PROTOCOL://$DEVICEDEMO_SERVICE_HOST:$DEVICEDEMO_SERVICE_PORT/" \
            "$DEVICEDEMO_SERVICE_PROTOCOL://$DEVICEDEMO_SERVICE_HOST:$DEVICEDEMO_SERVICE_PORT/"
    fi

    # Make devices an admin
    get_or_add_user_project_role admin devices service
}

# create_devices_cache_dir() - Part of the init_devices() process
function create_devices_cache_dir {
    # Create cache dir
    sudo install -d -o $STACK_USER $DEVICEDEMO_AUTH_CACHE_DIR
    sudo install -d -o $STACK_USER $DEVICEDEMO_AUTH_CACHE_DIR/api
    sudo install -d -o $STACK_USER $DEVICEDEMO_AUTH_CACHE_DIR/registry
}

# create_devices_data_dir() - Part of the init_devices() process
function create_devices_data_dir {
    # Create data dir
    sudo install -d -o $STACK_USER $DEVICEDEMO_DATA_DIR
    sudo install -d -o $STACK_USER $DEVICEDEMO_DATA_DIR/locks
}

# init_devices() - Initialize Devicedemo database
function init_devices {
    create_devices_cache_dir
    create_devices_data_dir

    # (Re)create devices database
    recreate_database devices utf8

    # Migrate devices database
    $DEVICEDEMO_BIN_DIR/devices-dbmanage upgrade
}

# start_devices() - Start running processes, including screen
function start_devices {
    run_process devices-api "$DEVICEDEMO_BIN_DIR/devices-api --config-file $DEVICEDEMO_CONF"

    echo "Waiting for devices-api ($DEVICEDEMO_SERVICE_HOST:$DEVICEDEMO_SERVICE_PORT) to start..."
    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget --no-proxy -q -O- http://$DEVICEDEMO_SERVICE_HOST:$DEVICEDEMO_SERVICE_PORT; do sleep 1; done"; then
        die $LINENO "devices-api did not start"
    fi
}

# stop_devices() - Stop running processes
function stop_devices {
    # Kill the devices screen windows
    for serv in devices-api; do
        stop_process $serv
    done
}

# cleanup_devices() - Remove residual data files, anything left over from previous
# runs that a clean run would need to clean up
function cleanup_devices {
    # Clean up dirs
    sudo rm -rf $DEVICEDEMO_AUTH_CACHE_DIR
    sudo rm -rf $DEVICEDEMO_CONF_DIR
    sudo rm -rf $DEVICEDEMO_OUTPUT_BASEPATH
    sudo rm -rf $DEVICEDEMO_DATA_DIR
}

# This is the main for plugin.sh
if is_service_enabled devices-api; then
    if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
        # Set up system services
        echo_summary "Configuring system services for Devicedemo"
        preinstall_devices

    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        echo_summary "Installing Devicedemo"
        # Use stack_install_service here to account for vitualenv
        stack_install_service devices

    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        echo_summary "Configuring Devicedemo"
        configure_devices
        # Get devices keystone settings in place
        create_devices_accounts

    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        # Initialize devices
        echo_summary "Initializing Devicedemo"
        init_devices

        # Start the Devicedemo API and Devicedemo processor components
        echo_summary "Starting Devicedemo"
        start_devices
    fi

    if [[ "$1" == "unstack" ]]; then
        echo_summary "Shutting Down Devicedemo"
        stop_devices
    fi

    if [[ "$1" == "clean" ]]; then
        echo_summary "Cleaning Devicedemo"
        cleanup_devices
    fi
fi


# Restore xtrace
$XTRACE

