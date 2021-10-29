# fullname="USER INPUT"
read -p "Enter fullname: " fullname
# user="USER INPUT"
read -p "Enter user: " user
echo $fullname $user

echo foo bar | jq --raw-input 'split( " ")'