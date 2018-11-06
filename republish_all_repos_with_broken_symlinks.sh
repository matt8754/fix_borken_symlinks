pulpAdminPassword=$(grep ^default_password /etc/pulp/server.conf | cut -d' ' -f2)
orgName="CEE-Ops"

wait_for_tasks() {
	tasks=$(pulp-admin -u admin -p $pulpAdminPassword tasks list --state=running,waiting | grep -c "Task Id")
	while [ $tasks -gt 0 ]; do
		echo "$(date): waiting for $tasks tasks to complete.."
		sleep 10
		tasks=$(pulp-admin -u admin -p $pulpAdminPassword tasks list --state=running,waiting | grep -c "Task Id")
	done
}

echo "$(date): publishing base repos.."
for repo in $(cat base_repos_to_fix.txt); do
	curl -i -H "Content-Type: application/json" -X POST -d "{\"id\":\"$repo\",\"override_config\":{\"force_full\":true}}" -u admin:$pulpAdminPassword https://$(hostname -f)/pulp/api/v2/repositories/$repo/actions/publish/
done

echo "$(date): publish of base repos kicked off, waiting for their completion"
wait_for_tasks

echo "$(date): publishing CV version repos.."
for repo in $(cat CVversion_repos_to_fix.txt); do
	baserepo=$(su - postgres -c "psql foreman -c \"COPY (SELECT label FROM katello_repositories WHERE pulp_id = '${repo}') TO STDOUT;\"")
	baserepo="${orgName}-${baseRepo}"
	curl -i -H "Content-Type: application/json" -X POST -d "{\"id\":\"${repo}_clone\",\"override_config\":{\"source_repo_id\":\"${baserepo}\",\"source_distributor_id\":\"${baserepo}\"}}" -u admin:$pulpAdminPassword https://$(hostname -f)/pulp/api/v2/repositories/$repo/actions/publish/
done

echo "$(date): publish of CV version repos kicked off, waiting for their completion"
wait_for_tasks

echo "$(date): publishing repos of CVs promoted to LEs.."
for repo in $(cat CVpromoted_repos_to_fix.txt); do
	LE=$(su - postgres -c "psql foreman -c \"COPY (SELECT content_view_version_id,environment_id,label FROM katello_repositories WHERE pulp_id = '${repo}') TO STDOUT DELIMITER',';\"")
	# extract from the string a tripple ${cvid},${LE},${baserepo}
	baserepo=${LE##*,}
	cvid=${LE%%,*}
	LE=${LE%,*}
	LE=${LE#*,}
	# cv_id will be 14_1 major_minor version of the CV version ID $cvid
	cv_id=$(su - postgres -c "psql foreman -c \"COPY (SELECT major,minor FROM katello_content_view_versions WHERE id = '${cvid}') TO STDOUT DELIMITER'_';\"")
	cvlabel=$(su - postgres -c "psql foreman -c \"COPY (SELECT katello_content_views.label FROM katello_content_views INNER JOIN katello_content_view_versions ON katello_content_view_versions.content_view_id = katello_content_views.id WHERE katello_content_view_versions.id = '${cvid}') TO STDOUT;\"")
	baserepo="${orgName}-${cvlabel}-${cv_id}-${baserepo}"
	curl -i -H "Content-Type: application/json" -X POST -d "{\"id\":\"${repo}_clone\",\"override_config\":{\"source_repo_id\":\"${baserepo}\",\"source_distributor_id\":\"${baserepo}\"}}" -u admin:$pulpAdminPassword https://$(hostname -f)/pulp/api/v2/repositories/$repo/actions/publish/
done

echo "$(date): publish of repos of CVs promoted to LEs kicked off, waiting for their completion"
wait_for_tasks


