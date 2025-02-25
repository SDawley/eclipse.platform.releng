#!/bin/sh
#*******************************************************************************
# Copyright (c) 2016, 2018 GK Software SE and others.
#
# This program and the accompanying materials
# are made available under the terms of the Eclipse Public License 2.0
# which accompanies this distribution, and is available at
# https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#     Stephan Herrmann - initial API and implementation
#********************************************************************************

REPO_BASE=${WORKSPACE}/archive
REPO=${REPO_BASE}/repo-${REPO_ID}
PDE=org/eclipse/pde

# load versions from the baseline (to avoid illegal double-upload):
source ${WORKSPACE}/baseline.txt

wget https://ci.eclipse.org/releng/job/CBIaggregator/${REPO_ID}/artifact/*zip*/archive.zip
unzip archive.zip

if [ ! -d ${REPO} ]
then
	echo "No repo at ${REPO}"
	exit 1
fi

echo "==== Copy artifacts from ${REPO}/${PDE} ===="

if [ -d ${PDE} ]
then
	/bin/rm -r ${PDE}/*
else
	mkdir -p ${PDE}
fi
cp -r ${REPO}/${PDE}/* ${PDE}/


echo "==== UPLOAD ===="

SETTINGS=/home/jenkins/.m2/settings-deploy-ossrh-pde.xml
MVN=/opt/tools/apache-maven/latest/bin/mvn

/bin/mkdir .log

function same_as_baseline() {
	simple=`basename $1`
	name=`echo $simple | sed -e "s|\(.*\)-.*|\1|" | tr '.' '_'`
	version=`echo $simple | sed -e "s|.*-\(.*\).pom|\1|"`
	base_versions=`eval echo \\${VERSION_$name}`
	if [ -n $base_versions ]
	then
		local base_single
		while read -d "," base_single
		do
			if [ $base_single == $version ]; then
				return 0
			fi
		done <<< "$base_versions"
		if [ $base_single == $version ]; then
			return 0
		fi
	else
		echo "Plug-in ${name}: ${version} seems to be new"
		return 1
	fi
	echo "different versions for ${name}: ${version} is not in ${base_versions}"
	return 1
}

for pomFile in org/eclipse/pde/*/*/*.pom
do
	xmllint --xpath "/*[local-name()='project']/*[local-name()='version']" $pomFile | grep SNAPSHOT
	snapshot=$?
	if [ $snapshot == 0 ]; then
		URL=https://repo.eclipse.org/content/repositories/eclipse-snapshots/
		REPO=repo.eclipse.org
	else
		URL=https://oss.sonatype.org/service/local/staging/deploy/maven2/
		REPO=ossrh
	fi

  if same_as_baseline $pomFile; then
	  echo "Skipping file $pomFile which is already present in the baseline"
  else
	  file=`echo $pomFile | sed -e "s|\(.*\)\.pom|\1.jar|"`
	  sourcesFile=`echo $pomFile | sed -e "s|\(.*\)\.pom|\1-sources.jar|"`
	  javadocFile=`echo $pomFile | sed -e "s|\(.*\)\.pom|\1-javadoc.jar|"`
	
	  echo "${MVN} -f pde-pom.xml -s ${SETTINGS} gpg:sign-and-deploy-file -Durl=${URL} -DrepositoryId=${REPO} -Dfile=${file} -DpomFile=${pomFile}"
	  
	  ${MVN} -f pde-pom.xml -s ${SETTINGS} gpg:sign-and-deploy-file \
	     -Durl=${URL} -DrepositoryId=${REPO} \
	     -Dfile=${file} -DpomFile=${pomFile} \
	     >> .log/artifact-upload.txt

		if [ -f "${sourcesFile}" ]; then
		  echo -e "\t${sourcesFile}"
		  ${MVN} -f pde-pom.xml -s ${SETTINGS} gpg:sign-and-deploy-file \
		     -Durl=${URL} -DrepositoryId=${REPO} \
		     -Dfile=${sourcesFile} -DpomFile=${pomFile} -Dclassifier=sources \
		     >> .log/sources-upload.txt
		fi

		if [ -f "${javadocFile}" ]; then
		  echo -e "\t${javadocFile}"
		  ${MVN} -f pde-pom.xml -s ${SETTINGS} gpg:sign-and-deploy-file \
		     -Durl=${URL} -DrepositoryId=${REPO} \
		     -Dfile=${javadocFile} -DpomFile=${pomFile} -Dclassifier=javadoc \
		     >> .log/javadoc-upload.txt
		fi
  fi
done

/bin/ls -la .log

/bin/grep "BUILD FAILURE" .log/*
if [ "$?" -eq 0 ]; then
	echo "Deployment failed, see logs for details"
	exit 1
fi

