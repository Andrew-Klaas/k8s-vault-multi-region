#!/bin/bash
#https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/#std-label-install-mdb-community-ubuntu

sudo apt-get install -y gnupg curl vim netcat awscli
curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg \
   --dearmor


echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt-get update
sudo apt-get install -y mongodb
sudo apt-get update

#optional
# echo "mongodb-org hold" | sudo dpkg --set-selections
# echo "mongodb-org-database hold" | sudo dpkg --set-selections
# echo "mongodb-org-server hold" | sudo dpkg --set-selections
# echo "mongodb-mongosh hold" | sudo dpkg --set-selections
# echo "mongodb-org-mongos hold" | sudo dpkg --set-selections
# echo "mongodb-org-tools hold" | sudo dpkg --set-selections

#Enable remote access (insecure for demo purposes)
sudo sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongodb.conf

sudo systemctl start mongodb

#create a her doc
cat <<EOF > mongodb_init.js
use admin
db.createUser(
  {
    user: "UserAdmin",
    pwd: "password",
    roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
  }
)
EOF
mongo < mongodb_init.js

sudo cat <<EOF > /tmp/mongodump.sh
mongodump --archive --gzip | aws s3 cp - s3://ak-tf-test-demo-bucketw/mongo.backup
EOF
sudo chmod 755 /tmp/mongodump.sh

sudo echo "* * * * * /tmp/mongodump.sh" | crontab -

sudo systemctl restart mongodb

#mongosh
