
DIR_DEVICEDEMO=$DEST/devicedemo

function install_devicedemo {
    cd $DIR_DEVICEDEMO
    sudo pip install -r requirements.txt
    sudo pip install -r test-requirements.txt
}

function configure_devicedemo {
    sed -i -e "s|password = password|password = abcd1234|g;" $DIR_DEVICEDEMO/etc/devicedemo/devicedemo.conf
    #local devicedemo_domain=$(get_or_create_domain $DOMAIN_NAME)
    #local devicedemo_project=$(get_or_create_project $PROJECT_NAME $DOMAIN_NAME)
    #local member_role=$(get_or_create_role Member)

    openstack project create --domain default --description "Service Project" service
    openstack user create --domain default --password-prompt devicedemo
    openstack role add --project service --user devicedemo admin
    openstack service create --name devicedemo --description "OpenStack Devicedemo" devicedemo
    openstack endpoint create --region RegionOne devicedemo public http://127.0.0.1:9000
    openstack endpoint create --region RegionOne devicedemo internal http://127.0.0.1:9000
    openstack endpoint create --region RegionOne devicedemo admin http://127.0.0.1:9000

}

function init_devicedemo {
    export PYTHONPATH=$DIR_DEVICEDEMO

    cd $DIR_DEVICEDEMO
    python devicedemo/cmd/api.py --config-dir etc/devicedemo
}

function configure_tests_settings {
}

function uninstall_devicedemo {
    cd $DEST
    sudo rm -rf devicedemo
}
