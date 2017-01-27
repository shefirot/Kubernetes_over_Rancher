#!/bin/bash
#set -x
#author David Gonzalez Pozo dgp.asir//@//gmail//.com
#Mensaje de uso general donde se define la llamada al script
#Si no se define un usuario, por defecto se creara root Pass
Uso="Uso: kubernetes_ono_click.sh 1:IP_rancher_server 2:IP_rancher_host [3:Usuario_rancher_server (por defecto root) 4:Clave_rancher_server (por defecto Pass) 5:Usuario_conexion_ssh(por defecto core)]"
# $? devolvera mayor que 0 en caso de error

#Establece el usuario por defecto para ssh
if [ -z $5 ]
  then
    echo "Establecido el usuario de ssh por defecto a core"
    echo
    user="core"
  else
    user=$5
fi

#Comprueba que las dos IPs pasadas por parametro son correctas redirecciona a la salida estandar y devuelve un error
#Comprueba la comunicacion entre los hosts y que tengas persmisos de sudo

ssh $user@$1 sudo ping $2 -c 1 &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error en la ip del rancher server, rancher host o usuario de ssh"
    echo $Uso
    exit 1
fi

ssh $user@$2 sudo ping $1 -c 1 &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error en la ip del rancher server, rancher host o usuario de ssh"
    echo $Uso
    exit 1
fi


#Establece la IP el puerto para el rancher server
ip=$1
iP_Puerto="$1:8080"

#Establece el usuario y la clave de rancher
if [ -z $3 ]
  then
    userRancher='"root"'
  else
    userRancher='"'$3'"'
fi
if [ -z $4 ]
  then
    claveRancher='"Pass"'
  else
    claveRancher='"'$4'"'
fi


#Instalacion de docker de rancher
echo
echo -n "Creamos el docker de rancher server, tardara unos minutos"
ssh $user@$1 sudo docker run --name rancher-server -d --restart=always -p 8080:8080 rancher/server:stable &>> /dev/null
if [ $? != 0 ]  
  then   
    echo "Error al instalar el docker de rancher" 
    exit 2
fi


#Espera activa hasta que el servicio este disponible
curl -s $iP_Puerto &>> /dev/null
until [  $? == 0 ]; do
  echo -n "."
  sleep 1s
  curl -s $iP_Puerto &>> /dev/null
done
echo "."
sleep 10s


echo
echo "Obtenemos el token de autenticacion"
echo
token=($(curl -X POST $iP_Puerto/v1/apikey | jq '. | .publicValue, .secretValue')) &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al obtener el token de rancher" 
    exit 3
fi


echo
echo "Borrar el entorno por defecto de cattle"
echo
curl -u "${token[0]}":"${token[1]}" \
-X DELETE \
$iP_Puerto/v1/projects/1a5 | jq . &>> /dev/null
if [ $? != 0 ]
  then
    echo "Warning al borrar el entorno de cattle, sigue la ejecuccion." 
fi


echo
echo "Obtenemos el id del template de kubernetes"
echo
envTemplate=($(curl -u "${token[0]}":"${token[1]}" $iP_Puerto/v2-beta/projecttemplates/ | jq '.data[] | select( .description=="Default Kubernetes template") | {idTemplateKuberntes: .id}'))  &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al obtener el id del template de rancher" 
    exit 4
fi


echo
echo "Creamos el enviroment"
echo
id_env=($(curl -u "${token[0]}":"${token[1]}" \
-X POST \
-H 'Accept: application/json' \
-H 'Content-Type: application/json' \
-d '{"description":"Entorno de pruebas de Kubernetes", "name":"K8s2", "projectTemplateId":'${envTemplate[2]}', "allowSystemRole":false, "members":[], "virtualMachine":false, "servicesPortRange":null}' \
$iP_Puerto/v2-beta/projects/ | jq '. | .id, .data.fields.orchestration' )) &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al crear el enviroment de kubernetes" 
    exit 5
fi


#Hay que esperar unos segundos hasta que se cree correctamente el enviroment
echo
echo "Obtencion del comando para añadir cada host al enviroment, tardara unos segundos"
echo
sleep 5s
subEnviroment=($(curl -X POST -u "${token[0]}":"${token[1]}" $iP_Puerto/v1/registrationtokens?projectId=$(echo "${id_env[0]}" | sed 's|"||g') | jq ' .| {idSubEnviroment: .id}')) &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al obtener el comando para añadir hosts" 
    exit 6
fi
sleep 5s

#quita las comillas dobles sobre el subenviroment
aux=$(echo "${subEnviroment[2]}" | sed 's|"||g')
comando=($(curl -u "${token[0]}":"${token[1]}" $iP_Puerto/v1/registrationtokens/$aux | jq ' .| .command'))   &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al obtener el comando para añadir hosts" 
    exit 7
fi


#ejecutanos el comando para añadir el host
aux=$(echo "${comando[@]}" | sed 's|"||g')


#Se añade el host al segundo equipo pasado por argumento
echo
echo "Añadimos el host al enviroment de kubernetes"
echo
ssh $user@$2 $aux   &>> /dev/null
if [ $? != 0 ]
  then
    echo "Error al añadir el host" 
    exit 8
fi


echo
echo "Creamos el usuario $userRancher con clave $claveRancher."
echo
curl -X POST -H 'Content-Type: application/json' $iP_Puerto/v1/localAuthConfig -d '{"type":"localAuthConfig","accessMode":"unrestricted","enabled":true,"name":'$userRancher',"username":'$userRancher',"password":'$claveRancher'}' &>> /dev/null
if [ $? != 0 ]
  then
    echo "Warning no se ha podido crear el usuario $userRancher con clave $claveRancher."
    echo
fi


echo
echo "Comando para el resto de hosts: $aux"
