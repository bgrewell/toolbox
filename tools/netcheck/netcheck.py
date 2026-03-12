#!/usr/bin/python3

""" netcheck.py : Review relevant information about network interfaces and perform connectivity tests """

__author__     = 'Brent Elliott, Ben Grewell <benjamin.grewell@intel.com>'
__email__      = 'brent.j.elliott@intel.com'
__license__    = 'MIT'
__version__    = '0.4.0'
__status__     = 'Development'
__copyright__  = 'Copyright 2023, Intel Corporation'
__github__     = 'https://github.com/bgrewell/toolbox'

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile


#----------------------------------------------------------------------------------------------------------------------
# main - primary netcheck implementation
#----------------------------------------------------------------------------------------------------------------------
def main():

    # Define several globals to simplify code organization
    global errors
    global args

    # Track errors and warnings experienced throughout execution
    errors = {}

    # Initialize JSON response
    response = {}

    # Process command-line arguments
    args = process_args()

    # Perform requested operations
    if args.interfaces or args.pcie or args.vlans:
        (response['interfaces'], response['openvswitch']) = process_ip_addr()
    if args.routes:
        response['routes'] = process_ip_route()
    if args.dns:
        response['dns'] = process_resolvectl()
    if args.test:
        test_connectivity()
    if args.json:
        print(json.dumps(response))

#----------------------------------------------------------------------------------------------------------------------
# process_args - Process all arguments, set defaults, handle basic arg based behaviors
#----------------------------------------------------------------------------------------------------------------------
def process_args():
    # Parse command-line parameters
    parser = argparse.ArgumentParser(
                description='Review relevant information about network interfaces and perform connectivity tests',
                epilog='For more details, see ' + __github__,
                allow_abbrev=True)

    oper_group = parser.add_argument_group('Operational Parameters')
    filt_group = parser.add_argument_group('Formatting and Filtering')
    disp_group = parser.add_argument_group('Display Tables')

    oper_group.add_argument('-t', '--test',
                            action='store_true',
                            help='Perform connectivity tests')
    oper_group.add_argument('-j', '--json',
                            action='store_true',
                            help='Export all information in json format')
    oper_group.add_argument('-o', '--ovs',
                            action='store_true',
                            help='Perform Open vSwitch parsing (SUDO required)')
    oper_group.add_argument('-v', '--version',
                            action='store_true',
                            help='Display version information')

    filt_group.add_argument('-u', '--up',
                            action='store_true',
                            help='Only report interfaces that are UP')
    filt_group.add_argument('-s', '--summary',
                            action='store_true',
                            help='Print shorter summary of interfaces and VLANs')
    filt_group.add_argument('-b', '--barebones',
                            action='store_true',
                            help='Barebones table formatting (narrow, easy import)')

    disp_group.add_argument('-a', '--all',
                            action='store_true',
                            help='Display all tables')
    disp_group.add_argument('-c', '--clear',
                            action='store_true',
                            help='Clear the console before displaying tables')
    disp_group.add_argument('-I', '--interfaces',
                            action='store_true',
                            help='Display interfaces table')
    disp_group.add_argument('-V', '--vlans',
                            action='store_true',
                            help='Display vlans table')
    disp_group.add_argument('-D', '--dns',
                            action='store_true',
                            help='Display dns table')
    disp_group.add_argument('-R', '--routes',
                            action='store_true',
                            help='Display routes table')
    disp_group.add_argument('-P', '--pcie',
                            action='store_true',
                            help='Display PCIe table')

    args = parser.parse_args()

    # Clear screen
    if args.clear:
        subprocess.run(['clear'], shell=False)

    # Show version information and exit
    if args.version:
        print(os.path.basename(__file__) + ' version ' + __version__)
        sys.exit(0)

    # If no tables or tests are selected, default to interfaces and vlans
    if not (args.interfaces or args.vlans or args.dns or args.routes or args.pcie or args.test):
        args.interfaces = True
        args.vlans = True

    # Handle --all flag by setting all tables to true (test must be explicitly executed)
    if args.all:
        args.interfaces = True
        args.vlans = True
        args.dns = True
        args.routes = True
        args.pcie = True

    return args

#----------------------------------------------------------------------------------------------------------------------
# process_ip_addr - Perform ip addr show and process results
#----------------------------------------------------------------------------------------------------------------------
def process_ip_addr():

    itable = []     # interfaces
    vtable = []     # vlans
    ptable = []     # pcie devices

    interfaces = {}
    openvswitch = {}

    # Specify which fields are stored in which columns for itable
    col_interface    =  1
    col_macaddress   =  2
    col_state        =  3
    col_ipaddress    =  4
    col_driver       =  5

    if args.summary:
        col_bus      =  6
        col_dprrf    =  7
        col_port     =  8
    else:
        col_fw       =  6
        col_bus      =  7
        col_speed    =  8
        col_port     =  9
        col_altnames = 10

    # Get output of ip addr show command and create a JSON structure on which to hang additional useful information
    try:
        result = subprocess.run(['ip', '-detail', '-json', 'address', 'show'],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result.check_returncode()
        interfaces = json.loads(result.stdout.decode())

    except subprocess.CalledProcessError as e:
        print(f"\nERROR: 'ip' command returned non-zero exit status {e.returncode}.")
        print(f"       {e}")
        sys.exit(120)
    except FileNotFoundError:
        print("\nERROR: Dependency 'ip' not found. Please install 'ip' or troubleshoot access and retry.")
        sys.exit(121)
    except Exception as e:
        print("\nERROR: Dependency 'ip' is failing. Please troubleshoot the command 'ip address show' and retry.")
        print(f"       {e}")
        sys.exit(122)

    # Additional JSON entry to store human readable output
    human = {}

    # Parse through each network interface returned by ip addr show and collect additional information along the way
    ovs_found = False
    for entry in interfaces:

        # Omit lo interface (not useful) and if the --up flag is used omit any interfaces that are not in the UP state
        if (entry['ifname'] != 'lo' and (entry['operstate'] == 'UP' or not args.up)):
            process_interface(entry, human, itable, vtable, ptable)

            if entry['driver'] == "ovs":
                ovs_found = True

    # Perform OVS post-processing if specified (not default since ovs commands require sudo for basic info access)
    if ovs_found and args.ovs:
        try:
            result = subprocess.run(['sudo', 'ovs-vsctl', 'show'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            result.check_returncode()

        except subprocess.CalledProcessError as e:
            flag_error = True
            print(f"\nWARNING: 'ovs-vsctl' command returned non-zero exit status {e.returncode}.")
            print(f'         {str(e)}')
            print(f'         Information will be missing from the output.')
        except FileNotFoundError:
            flag_error = True
            print(f"\nWARNING: Dependency 'ovs-vsctl' not found. Please install 'ovs-vsctl' or " + \
                   "troubleshoot access and retry.")
            print(f'         Information will be missing from the output.')
        except Exception as e:
            flag_error = True
            print(f"\nWARNING: Dependency 'ovs-vsctl' is failing.")
            print(f'         {str(e)}')
            print(f'         Information will be missing from the output.')

        # Process ovs-vsctl output
        openvswitch = {"bridges": {}}
        current_bridge = None
        current_port = None
        current_port_values = {}
        bridge_lookup = {}

        for line in result.stdout.decode().split('\n'):
            line = line.strip()

            # Check if the line starts with "Bridge"
            if line.startswith('Bridge '):
                current_bridge = line.lstrip('Bridge').strip()
                openvswitch['bridges'][current_bridge] = {"ports": {}}

            # Check if the line starts with "Port"
            elif line.startswith('Port '):
                # If the current port has values, commit them to the dictionary
                if current_port:
                    openvswitch['bridges'][current_bridge]['ports'][current_port] = current_port_values
                    current_port_values = {}

                current_port = line.lstrip('Port').strip()
                bridge_lookup[current_port] = current_bridge

            # Check if the line has key-value pair
            elif ':' in line:
                key, value = line.split(':')
                current_port_values[key.strip()] = value.strip()

            # Add the last port to the dictionary
            if current_port:
                openvswitch['bridges'][current_bridge]['ports'][current_port] = current_port_values

        # Overwrite information in the itable with ovs updated values
        for entry in itable:
            interface = entry[col_interface]

            # Replace bridge physical device name with PORT for Open vSwitch bridge interfaces
            if entry[col_driver] == 'ovs':
                if 'bridges' in openvswitch and interface in openvswitch['bridges']:
                    macaddress = entry[col_macaddress]
                    for lookup in itable:
                        if lookup[col_macaddress] == macaddress and entry[col_interface] != lookup[col_interface]:
                            entry[col_port] = f'[{lookup[col_interface]}]'

            # Replace PORT with bridge name and BUS with TAG for Open vSwitch ports
            if entry[col_bus] == 'tap':
                if interface in bridge_lookup:
                    bridge = bridge_lookup[interface]

                    entry[col_port] = f'[{bridge}]'
                    if 'bridges' in openvswitch and bridge in openvswitch['bridges']:
                        if 'ports' in openvswitch['bridges'][bridge]:
                            if interface in openvswitch['bridges'][bridge]['ports']:
                                entry[col_driver] = 'ovs'
                                if 'tag' in openvswitch['bridges'][bridge]['ports'][interface]:
                                    entry[col_bus] = '[VID ' + \
                                                     openvswitch['bridges'][bridge]['ports'][interface]['tag'] + ']'
                                else:
                                    entry[col_bus] = '[ACCESS]'

    # If not exporting via JSON, prepare and print tables
    if not args.json:

        # Sort interface table by State (IP first, then DOWN, others alphabetically after), Driver, and Interface
        itable = sorted(itable, key=lambda x:
                        (x[col_driver], x[col_port], x[col_interface]))

        itable = sorted(itable, key=lambda x:
                        (0 if x[col_state] == 'UP' else 1 if x[col_state] == 'DOWN' else 2, x[col_state]))

        # Sort VLAN table by Link, then VID
        vtable = sorted(vtable, key=lambda x: (x[2], x[3]))

        # Sort PCIe table by BUS ID
        ptable = sorted(ptable, key=lambda x: x[2])

        # Add Column Headers to tables
        header_summary   = ['ID', 'INTERFACE', 'MAC ADDRESS', 'STATE', 'IP ADDRESSES',
                            'DRIVER', 'BUS', 'SPEED', 'PORT']
        header_barebones = ['ID', 'INT',       'MAC ADDRESS', 'STATE', 'IP ADDRESSES',
                            'DRIVER', 'F/W',      'BUS', 'SPEED', 'PORT', 'ALTNAMES']
        header_default   = ['ID', 'INTERFACE', 'MAC ADDRESS', 'STATE', 'IP ADDRESSES',
                            'DRIVER', 'FIRMWARE', 'BUS', 'SPEED', 'PORT', 'ALTNAMES']
        header = header_summary if args.summary else (header_barebones if args.barebones else header_default)

        itable.insert(0, header)
        vtable.insert(0, ['ID', 'INTERFACE', 'LINK', 'VID', 'MAC ADDRESS', 'STATE', 'IP ADDRESSES'])
        ptable.insert(0, ['ID', 'INTERFACE', 'BUS', 'DESCRIPTION'])

        # Show tables requested
        if args.interfaces:
            if len(itable) > 1:
                print_table(args, 'Physical Interfaces', itable)
            else:
                print('No network interfaces found.')
        if args.vlans:
            if len(vtable) > 1:
                print_table(args, 'VLAN Interfaces', vtable)
            else:
                print('No VLANs configured.')
        if args.pcie:
            if len(ptable) > 1:
                print_table(args, 'PCIe Device Details', ptable)
            else:
                print('No PCIe devices corresponding to network interfaces found.')

    return interfaces, openvswitch

#----------------------------------------------------------------------------------------------------------------------
# process_interface  - Process ip -detail addr show results, execute ethtool commands, and cleanse data
#----------------------------------------------------------------------------------------------------------------------
def process_interface(entry, human, itable, vtable, ptable):
    # Create empty default values for any missing required keys from ip addr show command
    for key in ['ifindex', 'ifname', 'link', 'address', 'operstate', 'ip']: entry.setdefault(key, '')

    # Create multiline listing for IPv4 addresses for human output
    ip_addresses = [f"{address['local']}/{address['prefixlen']}"
                    for address in entry['addr_info'] if address['family'] == 'inet']
    human['ip'] = '\n'.join(ip_addresses)

    # Create multiline listing for altnames for human output
    human['altnames'] = '\n'.join(entry.get('altnames', []))

    # Get ethtool driver output for interface
    flag_error = False
    try:
        result1 = subprocess.run(['ethtool', '-i', entry['ifname']], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result1.check_returncode()

        result2 = subprocess.run(['ethtool', entry['ifname']], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result2.check_returncode()

        eth_driver = result1.stdout.decode()
        eth_general = result2.stdout.decode()

    except subprocess.CalledProcessError as e:
        flag_error = True
        error_text  = f"\nWARNING: 'ethtool' command returned non-zero exit status {e.returncode}.\n"
        error_text += f'         {str(e)}'
    except FileNotFoundError:
        flag_error = True
        error_text  = f"\nWARNING: Dependency 'ethtool' not found. Please install 'ethtool' or troubleshoot " + \
                       "access and retry."
    except Exception as e:
        flag_error = True
        error_text  = f"\nWARNING: Dependency 'ethtool' is failing.\n"
        error_text += f'         {str(e)}'

    # If an ethtool related error was flagged provide warning only once (not for each interface)
    if flag_error:
        eth_driver  = ''
        eth_general = ''

        if 'ethtool' not in errors:
            errors.update({'ethtool': 'error'})
            print(error_text)
            print('         Information will be missing from the output.')

    # Extract relevant fields from ethtool output interpreted as key: value
    for row in (eth_driver + eth_general).split('\n'):
        pair = row.split(': ')
        if len(pair) == 2:
            key = pair[0].strip().lower().replace(' ', '-')
            value = pair[1].strip().replace('\t', ',')
            if key not in ['supported-link-modes', 'advertised-link-modes', 'netlink-error', 'current-message-level']:
                entry[key] = value

    # Create empty default values for any missing required keys from ethtool commands
    for key in ['driver', 'firmware-version', 'bus-info', 'speed', 'port', 'altnames']: entry.setdefault(key, '')

    # Remove leading PCI domain prefix in bus info for human output
    human['bus'] = entry.get('bus-info', '').removeprefix('0000:')

    # Get lspci information for interface
    entry.setdefault('device-name', '')
    if human['bus'].lower() not in ['n/a', 'tap', '']:
        flag_error = False
        try:
            result = subprocess.run(['lspci', '-s', human['bus']], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            result.check_returncode()

        except subprocess.CalledProcessError as e:
            flag_error = True
            error_text  = f"\nWARNING: 'lspci' command returned non-zero exit status {e.returncode} for interface " + \
                           f"{entry['ifname']}.\n"
            error_text += f'         {str(e)}'
        except FileNotFoundError:
            flag_error = True
            error_text  = f"\nWARNING: Dependency 'lspci' not found. Please install 'lspci' or troubleshoot " + \
                           "access and retry."
        except Exception as e:
            flag_error = True
            error_text  = f"\nWARNING: Dependency 'lspci' is failing.\n"
            error_text += f'         {str(e)}'

        # If an lspci related error was flagged provide warning only once (not for each interface)
        if flag_error:
            if 'lspci' not in errors:
                errors.update({'lspci': 'error'})
                print(error_text)
                print('         Information will be missing from the output.')
        else:
            entry['device-name'] = result.stdout.decode().strip()

            if ': ' in entry['device-name']:
                entry['device-name'] = entry['device-name'].split(': ')[1].rstrip()
                ptable.append([ entry['ifindex'], entry['ifname'], human['bus'], entry['device-name'] ])

    # Clean up speed entries for human output
    speed_map = {
        'unknown!': '',               '1000mb/s': '1 Gb/s',         '2500mb/s': '2.5 Gb/s',
        '5000mb/s': '5 Gb/s',         '10000mb/s': '10 Gb/s',       '25000mb/s': '25 Gb/s',
        '40000mb/s': '40 Gb/s',       '50000mb/s': '50 Gb/s',       '100000mb/s': '100 Gb/s',
        '200000mb/s': '200 Gb/s',     '400000mb/s': '400 Gb/s',     '800000mb/s': '800 Gb/s'
    }
    human['speed'] = speed_map.get(entry['speed'].lower(), entry['speed'])

    # Clean up port entries for human output
    port_map = {
        'none': '',                   'twisted pair': 'BaseT',      'direct attach copper': 'DAC',
        'other': ''
    }
    human['port'] = port_map.get(entry['port'].lower(), entry['port'])

    # Clean up missing information for openvswitch
    if entry['driver'] in ['openvswitch', 'tun']:
        entry['port'] = "Virtual"
        human['port'] = "Virtual"
        entry['speed'] = ''
        human['speed'] = ''

        if entry['operstate'] == 'UNKNOWN':
            entry['operstate'] = ''

        if entry['driver'] == 'openvswitch':
            entry['driver'] = 'ovs'

    # Chop off firmware version beyond the first space for brevity in human output, remove commas
    human['firmware'] = entry['firmware-version'].split(' ')[0]
    human['firmware'] = human['firmware'].replace(',', '')

    # Add interface to the corresponding table (VLAN or Physical Interface)
    if entry['link']:

        # Obtain VLAN ID (VID) for VLANs
        if 'linkinfo' in entry and 'info_data' in entry['linkinfo'] and 'id' in entry['linkinfo']['info_data']:
            entry['vlanid'] = entry['linkinfo']['info_data']['id']
        else:
            entry['vlanid'] = ''

        # Add VLAN interface to vlan table
        vtable.append([ entry['ifindex'], entry['ifname'], entry['link'], entry['vlanid'], entry['address'],
                        entry['operstate'], human['ip'] ])

    else:
        if args.summary:
            # Add physical interface to interface table - summary mode
            itable.append([ entry['ifindex'], entry['ifname'], entry['address'], entry['operstate'], human['ip'],
                            entry['driver'], human['bus'], human['speed'], human['port'] ])

        else:
            # Add physical interface to interface table - default mode
            itable.append([ entry['ifindex'], entry['ifname'], entry['address'], entry['operstate'], human['ip'],
                            entry['driver'], human['firmware'], human['bus'], human['speed'], human['port'],
                            human['altnames'] ])

#----------------------------------------------------------------------------------------------------------------------
# process_ip_route   - Execute 'ip -detail -json route show' and parse response into Route Table (rtable)
#----------------------------------------------------------------------------------------------------------------------
def process_ip_route():

    rtable = []     # Route table

    # Get output of ip route command
    try:
        routes = json.loads(subprocess.run(['ip', '-detail', '-json', 'route'],
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode())
    except Exception:
        print("\nWARNING: Dependency 'ip' is missing or failing. Please troubleshoot the command 'ip route' and retry.")
        routes = {}

    # Populate human readable route table
    for route in routes:
        # Create empty default values for any missing required keys
        for key in ['dst', 'gateway', 'dev', 'protocol', 'metric']:
            if key not in route:
                route[key] = ''

        rtable.append([ route['dst'],
                        route['gateway'],
                        route['dev'],
                        route['protocol'],
                        route['metric'] ])
    if not args.json:
        rtable.insert(0, ['DESTINATION', 'GATEWAY', 'INTERFACE', 'PROTOCOL', 'METRIC'])

        if len(rtable) > 1:
            print_table(args, 'Route Table', rtable)
        else:
            print('No routes found.')

    return routes

#----------------------------------------------------------------------------------------------------------------------
# process_resolvectl - Execute resolvectl and parse response into DNS Table (dtable)
#----------------------------------------------------------------------------------------------------------------------
def process_resolvectl():

    dtable = []     # DNS table

    dns = {}

    try:
        dnsinfo = subprocess.run(['resolvectl'], stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode()
    except Exception:
        print("\nWARNING: Dependency 'resolvectl' is missing or failing. Please troubleshoot the command " + \
              "'resolvectl' and retry.")
        dnsinfo = ''

    # resolvectl has different formatting in different versions
    #   this filter will converge to a format where fields are not split across multiple lines
    dnsfilter = ''
    for line in dnsinfo.split('\n'):

        # ignore blank lines
        if len(line) > 0:

            # treat lines with ': ' as a key value pair line
            if ': ' in line:
                dnsfilter += '\n' + line.lstrip().rstrip()
            else:
                # treat lines with a '(' as a line containing a device name
                if '(' in line:
                    dnsfilter += '\n' + line.lstrip().rstrip()
                # treat line containing Global as a special "device" name
                elif line == 'Global':
                    dnsfilter += '\n' + line.lstrip().rstrip()
                # treat all other lines as a continuation of the previous field - so omit the newline
                else:
                    dnsfilter += ' ' + line.lstrip().rstrip()

    # Parse resolvectl output and add to dns object
    current_device = ''

    for line in dnsfilter.split('\n'):

        if ':' not in line:
            current_device = line
            if "(" in line:
                match = re.search(r'\(([\w0-9.\-_]+)\)', line)
                if match and len(match.groups()) >= 1:
                    current_device = match.group(1)
            if len(current_device) > 0:
                dns[current_device] = {}

        else:
            pair = line.split(': ')

            if len(pair) == 2:
                key = pair[0].lower().lstrip().rstrip().replace(' ', '-')

                reject_keys = [ ]
                if key not in reject_keys:
                    dns[current_device][key] = pair[1]

    # Create empty default values for any missing required keys
    for device in dns:
        for key in ['current-dns-server', 'dns-servers', 'dns-domain']:
            if key not in dns[device]:
                dns[device][key] = ''

    # Populate human readable DNS table
    for device in dns:
        if len(device) > 0:
            # Only append entries where there is one or more columns of data available
            if ( len(str(dns[device]['current-dns-server'])) > 0 or
                 len(str(dns[device]['dns-servers']))        > 0 or
                 len(str(dns[device]['dns-domain']))         > 0 ):

                dtable.append([ device,
                                dns[device]['current-dns-server'],
                                dns[device]['dns-servers'].replace(' ', '\n'),
                                dns[device]['dns-domain'].replace(' ', '\n') ])

    if not args.json:
        dtable.insert(0, ['INTERFACE', 'CURRENT SERVER', 'ALL SERVERS', 'DOMAINS'])

        if len(dtable) > 1:
            print_table(args, 'DNS Server Table', dtable)
        else:
            print('No DNS entries found.')

    return dns

#----------------------------------------------------------------------------------------------------------------------
# test_connectivity  - Perform network connectivity tests (employed with -t or --test flags)
#----------------------------------------------------------------------------------------------------------------------
def test_connectivity():

    # Connectivity Tests Table
    ttable = []

    # Perform connectivity tests
    ping1_pass = 'FAIL'
    ping1_value = 0
    ping2_pass = 'FAIL'
    ping2_value = 0
    wget_pass = 'FAIL'
    wget_value = ''
    nhop_pass = 'FAIL'
    nhop_value = ''
    nhop_gateway = ''
    throughput_pass = 'FAIL'
    throughput_value = ''

    # Test ping to public IP *without* DNS lookup required
    if not args.json: print('\r[ TESTING .     ] ', end='')
    try:
        ping1_test = subprocess.run(['ping', '-q', '-c', '5', '-i', '0.25', '-W', '0.5', '1.1.1.1'],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        match = re.search(r'rtt.*= ([0-9\.]+)/([0-9\.]+)/([0-9\.]+)/([0-9\.]+) ms',
                          ping1_test.stdout.decode().replace('\n', ' | '))
        ping1_value = 'unknown'
        if match is not None:
            if len(match.groups()) >= 3:
                ping1_value = match.group(2) + ' ms'

        if ping1_test.returncode == 0: ping1_pass = 'PASS'
    except Exception:
        print("\nWARNING: Dependency 'ping' is missing or failing. Direct IP connectivity results will be missing.")

    # Test ping to public IP *with* DNS lookup required
    if not args.json: print('\r[ TESTING ..    ] ', end='')
    try:
        ping2_test = subprocess.run(['ping', '-q', '-c', '5', '-i', '0.25', '-W', '0.5', 'www.cloudflare.com'],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        match = re.search(r'rtt.*= ([0-9\.]+)/([0-9\.]+)/([0-9\.]+)/([0-9\.]+) ms',
                          ping2_test.stdout.decode().replace('\n', ' | '))
        ping2_value = 'unknown'
        if match is not None:
            if len(match.groups()) >= 2:
                ping2_value = match.group(2) + ' ms'

        if ping2_test.returncode == 0: ping2_pass = 'PASS'
    except Exception:
        print("\nWARNING: Dependency 'ping' is missing or failing. Direct IP connectivity results will be missing.")

    # Test wget operation to public website - attempt to sense proxy usage (if properly configured)
    if not args.json: print('\r[ TESTING ...   ] ', end='')
    try:
        fd, temporary_filepath = tempfile.mkstemp()
        os.close(fd)
        wget_test = subprocess.run(['wget', '-O', temporary_filepath, 'https://www.cloudflare.com/'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.remove(temporary_filepath)

        match = re.search(r'Connecting to ([\w\d\.\-]+)', wget_test.stderr.decode())
        connecting_url = 'unknown'
        if match is not None:
            if len(match.groups()) >= 1:
                connecting_url = match.group(1)
                if connecting_url == 'www.cloudflare.com':
                    wget_value = 'Direct - no proxy detected'
                else:
                    wget_value = 'Proxy via ' + connecting_url

        if wget_test.returncode == 0: wget_pass = 'PASS'
    except Exception:
        print("\nWARNING: Dependency 'wget' is missing or failing. Web results will be missing.")

    # Ping the default gateway and extract latency, default gateway IP address and interface used to reach it
    if not args.json: print('\r[ TESTING ....  ] ', end='')
    try:
        # Lookup next hop IP to reach 1.1.1.1
        nhop_lookup = json.loads(subprocess.run(['ip', '--json', 'route', 'get', '1.1.1.1'],
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode())

        nhop_test = subprocess.run(['ping', '-q', '-c', '4', '-i', '0.25', '-W', '0.5', nhop_lookup[0]['gateway']],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        match = re.search(r'rtt.*= ([0-9\.]+)/([0-9\.]+)/([0-9\.]+)/([0-9\.]+) ms',
                          nhop_test.stdout.decode().replace('\n', ' | '))
        nhop_value = 'unknown'
        if match is not None:
            if len(match.groups()) >= 2:
                nhop_value = match.group(2) + ' ms'

        nhop_gateway = '(' + nhop_lookup[0]['gateway'] + ' via ' + nhop_lookup[0]['dev'] + ')'
        if nhop_test.returncode == 0: nhop_pass = 'PASS'
    except Exception:
        print("\nWARNING: Dependency 'ip' or 'ping' is missing or failing. Next Hop ping results will be missing.")

    # Quick download throughput test
    if not args.json: print('\r[ TESTING ..... ] ', end='')
    if wget_pass == 'PASS':

        test_url = 'https://cloudharmony1.cachefly.net/probe/test10mb.jpg'

        # Note: some URLs may be blocked on some networks

        # Azure CDN (Akamai)  - https://aka.azureedge.net/probe/test10mb.jpg
        # CacheFly CDN        - https://cloudharmony1.cachefly.net/probe/test10mb.jpg
        # Amazon CloudFront   - https://cloudharmony.com/probe/test10mb.jpg
        # Limelight CDN       - https://labtest-gartner.lldns.net/web-probe/test10mb.jpg
        # Cloudflare          - https://cloudflarecdn.cloudharmony.net/probe/test10mb.jpg
        # Azure CDN (Verizon) - https://ch.azureedge.net/probe/test10mb.jpg
        # Fastly CDN          - https://cloudharmony.global.ssl.fastly.net/probe/test10mb.jpg
        # Google Cloud CDN    - https://cdn-google.cloudharmony.net/probe/test10mb.jpg

        fd, temporary_filepath = tempfile.mkstemp()
        os.close(fd)
        throughput_test = subprocess.run([ 'wget', '--report-speed=bits', '--compression=none',
                                           '--no-check-certificate', '-O', temporary_filepath, test_url ],
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.remove(temporary_filepath)
        match = re.search(r'\(([\w\d\.\/ ]+)\) - ', throughput_test.stderr.decode())
        if match is not None:
            if len(match.groups()) >= 1:
                throughput_value = str(match.group(1)).replace('/','p')

        if throughput_test.returncode == 0: throughput_pass = 'PASS'

    if not args.json: print('\r', end='')

    ttable.append(['Test Description', 'Result', 'Details'])
    ttable.append(['Ping to Default Gateway', nhop_pass, nhop_gateway + " " + nhop_value])
    ttable.append(['Ping to Internet without DNS Lookup', ping1_pass, ping1_value])
    ttable.append(['Ping to Internet with DNS Lookup', ping2_pass, ping2_value])
    ttable.append(['Webpage Download', wget_pass, wget_value])
    ttable.append(['Brief Downlink Throughput', throughput_pass, throughput_value])

    # Create a list to store the test results
    test_results = []

    # Add test results to the list
    test_results.append({"test": "ping-gw", "result": nhop_pass, "rtt": nhop_value, "gateway": nhop_gateway})
    test_results.append({"test": "ping-internet", "result": ping1_pass, "rtt": ping1_value})
    test_results.append({"test": "ping-internet-with-dns", "result": ping2_pass, "rtt": ping2_value})
    test_results.append({"test": "webpage-load", "result": wget_pass, "details": wget_value})
    test_results.append({"test": "downlink-throughput", "result": throughput_pass, "rate": throughput_value})

    # If test mode is selected, perform test but do not show normal output (ignoring -j, -u, -s flags)
    if args.json:
        print(json.dumps(test_results))
    else:
        print_table(args, 'Connectivity Tests', ttable)

#----------------------------------------------------------------------------------------------------------------------
# print_table       - Print the passed table - assumes the first row is the column headers
#----------------------------------------------------------------------------------------------------------------------
def print_table(args, title, table):

    # Notes:
    # - Current implementation does not support newlines in the column headers or the table header
    # - Current implementation does not handle table header longer than the sum of columns below
    # - Current implementation does not support stretching out table (width or height)

    # Do not print tables with zero rows or columns
    if len(table) == 0:
        return
    elif len(table[0]) == 0:
        return

    # Determine table dimensions
    num_rows = len(table)
    num_cols = len(table[0])
    col_widths = [0] * num_cols
    row_heights = [1] * num_rows

    print_gridlines = True

    # Find the maximum size of each column (headers and data)
    for row in range(num_rows):
        for col in range(num_cols):
            for line in str(table[row][col]).split('\n'):
                this_width = len(line)
                if this_width > col_widths[col]:
                    col_widths[col] = this_width
            this_height = len(str(table[row][col]).split("\n"))
            if this_height > row_heights[row]:
                row_heights[row] = this_height

    # Find the total width of the table
    total_width = 0
    for col in range(num_cols):
        total_width += col_widths[col] + 3


    # Create top bar for table title
    if not args.barebones:
        print('\033[2;37m', end='')
        for col in range(num_cols):
            if col == 0:
                print('╭' + '─' * (col_widths[col] + 2), end='')
            else:
                print('─' * (col_widths[col] + 3), end='')
        print('╮')

    # Create table title
    if not args.barebones:
        print('│ \033[0m\033[0;30;47m' + title.center(total_width - 3) + '\033[0m\033[2;37m │')
    else:
        print('### ' + title + ' ###')

    # Create top bar for column headers
    if not args.barebones:
        for col in range(num_cols):
            if col == 0:
                print('├' + '─' * (col_widths[col] + 2), end='')
            else:
                print('┬' + '─' * (col_widths[col] + 2), end='')
        print('┤')

    # Print headers
    if not args.barebones:
        for col in range(num_cols):
            print('│\033[0m\033[1m' + str(table[0][col]).center(col_widths[col]+2) + '\033[0m\033[2;37m', end='')
        print('│')
    else:
        for col in range(num_cols):
            print(str(table[0][col]).rjust(col_widths[col]), end='|')
        print()


    # Create bottom bar for column headers
    if not args.barebones:
        for col in range(num_cols):
            if col == 0:
                print('├' + '─' * (col_widths[col] + 2), end='')
            else:
                print('┼' + '─' * (col_widths[col] + 2), end='')
        print('┤')

    # Print each row in the table
    if not args.barebones:
        for row in range(1,num_rows):
            for line in range(row_heights[row]):
                for col in range(num_cols):

                    split_text = str(table[row][col]).split("\n")
                    if len(split_text) > line:
                        text = split_text[line]
                    else:
                        text = ""

                    print('\033[0m\033[2;37m│\033[0m\033[1m', end='')

                    if text == "UP":
                        print('\033[92m' + text.rjust(col_widths[col] + 1) + '\033[0m\033[1m', end='')
                    elif text == "DOWN":
                        print('\033[31m' + text.rjust(col_widths[col] + 1) + '\033[0m\033[1m', end='')
                    elif text == "LOWERLAYERDOWN":
                        print('\033[31m' + text.rjust(col_widths[col] + 1) + '\033[0m\033[1m', end='')
                    else:
                        print('\033[0m' + text.rjust(col_widths[col] + 1) + '\033[1m', end='')
                    print(' ', end='')
                print('\033[0m\033[2;37m│')

            if print_gridlines and row < num_rows - 1:
                for col in range(num_cols):
                    if col == 0:
                        print('├\033[2;37m' + '─' * (col_widths[col] + 2), end='')
                    else:
                        print('┼\033[2;37m' + '─' * (col_widths[col] + 2), end='')
                print('\033[0m\033[2;37m┤')

    else:
        for row in range(1,num_rows):
            for line in range(row_heights[row]):
                for col in range(num_cols):

                    split_text = str(table[row][col]).split("\n")
                    if len(split_text) > line:
                        text = split_text[line]
                    else:
                        text = ""

                    print(text.rjust(col_widths[col]), end='|')
                print()

    # Create bottom bar for table
    if not args.barebones:
        for col in range(num_cols):
            if col == 0:
                print('╰' + '─' * (col_widths[col] + 2), end='')
            else:
                print('┴' + '─' * (col_widths[col] + 2), end='')
        print('╯\033[0m')
    else:
        print()

#----------------------------------------------------------------------------------------------------------------------
# Execute main function
if __name__ == '__main__':
    main()
#----------------------------------------------------------------------------------------------------------------------
