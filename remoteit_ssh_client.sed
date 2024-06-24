s/("device_name")/("-J", dest="device_name"); parser.add_argument('service_name')/
s/parser.parse_args()/parser.parse_known_args()\[0\]/

s/ device_name, key_id, key_secret_id/ device_name.device_name, key_id, key_secret_id/
s/device_details\[0\]\["services"\]\[0\]\["id"\]/next(x\["id"\] for x in device_details\[0\]\["services"\] if x\["name"\] == device_name.service_name)/

s/args.device_name/args/
s/^    details =/    return/
