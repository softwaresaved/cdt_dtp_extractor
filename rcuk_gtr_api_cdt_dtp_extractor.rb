#!/usr/bin/env ruby

# Uses RCUK GtR API/API 2 to extract project data and find all CDTs/DTPs.
# See http://gtr.rcuk.ac.uk/resources/GtR-1-API-v3.0.pdf for the API details.
# See http://gtr.rcuk.ac.uk/resources/GtR-2-API-v1.6.pdf for the API 2 details.

require 'open-uri'
require 'json'
require 'csv'
require 'fileutils'

# Returns a hash of project references pointing to the project details obtained from search results in JSON format
# (for other project details we need to further query the RCUK APIs).
# Also prune out all projects that are closed/expired/not active and those that have the grant type set to "Studentship" as they are not CDTs/DTPs.
def get_project_details(projects)
  project_details = {}
  projects.each do |project|
    project_reference = project["identifiers"]["identifier"].detect {|h| h["type"] == "RCUK"}["value"]
    project_details[project_reference] = {"title" => project["title"],
                                          "rcuk_id" => project["id"],
                                          "grant_category" => project["grantCategory"]} unless (project_reference.nil? or project["grantCategory"] == 'Studentship' or project["status"] == 'Closed')
  end
  project_details
end

# Base URL for accessing projects via RCUK GtR API
api_base_url = "http://gtr.rcuk.ac.uk/projects.json"

# Base URL for accessing projects via RCUK GtR API 2
api2_base_url = "http://gtr.rcuk.ac.uk/gtr/api/projects"
# Access the latest version 1.5 of API 2 and ask for response in JSON format
accept_header = "application/vnd.rcuk.gtr.json-v5"
# Number of results to be returned per page; default 20, max 100.
results_per_page = 100
# Search for projects mentioning any of the following search terms
search_terms = ['cdt', 'dtc', 'dtp', '"doctoral training centre"', '"centre for doctoral training"']
# Search for all projects that have the above search terms in the default search fields
api2_search_url = api2_base_url + "?s=#{results_per_page}&q=" + search_terms.map { |term| URI::encode(term) }.join('+')

# Get the paged search results back (returns only the first page along with the number of total
# pages and and the total number of results to be retrieved via successive calls)
puts "\n" + "#" * 80 +"\n\n"
puts "Getting search results for CDTs/DTPs from #{api2_search_url}"
search_results = []

begin
  search_results = JSON.load(open(api2_search_url, "Accept" => accept_header))
rescue Exception => ex
  puts "Failed to get anything out of #{api2_search_url}. An error of type #{ex.class} occurred, the reason being: #{ex.message}."
  Kernel.abort()
end

# total number of result pages
total_pages = search_results["totalPages"]
# total number of results on all pages
total_results = search_results["totalSize"]

# Current page number (equals 1 initially after the first query)
page = search_results["page"]

puts "Result stats: total number of pages = #{total_pages}; total number of projects = #{total_results}."

projects = {}

puts "Retrieving #{search_results["size"]} CDT/DTP projects from the results page no. #{page}."
# Get the projects from the first page
projects = projects.merge(get_project_details(search_results["project"]))

for current_page in page + 1 .. total_pages
  paged_search_url = api2_search_url + "&p=#{current_page}"
  puts "\n" + "#" * 80 +"\n\n"
  begin
    # Retrieve results from the current page
    puts "Quering #{paged_search_url}"
    search_results = JSON.load(open(paged_search_url, "Accept" => accept_header))
  rescue Exception => ex
    puts "Failed to get anything out of #{paged_search_url}. An error of type #{ex.class} occurred, the reason being: #{ex.message}."
  else
    # Get projects from this page
    puts "Retrieving #{search_results["size"]} CDT/DTP projects from the results page no. #{current_page}."
    projects = projects.merge(get_project_details(search_results["project"]))
  end
end

puts "\n" + "#" * 80 +"\n\n"
puts "Retrieved a total of #{projects.length} CDT/DTP projects."

puts projects.keys.to_s

# For each of the project references, use RCUK GtR API to access the project data and extract further project info.
projects.keys.each do |project_reference|
  project_url = api_base_url + "?ref=#{project_reference}"
  puts "\n" + "#" * 80 +"\n\n"
  begin
    puts "Retrieving project details for project #{project_reference} from #{project_url}"
    project_details_json = JSON.load(open(project_url))
  rescue Exception => ex
    puts "Failed to get project data from #{project_url}. An error of type #{ex.class} occurred, the reason being: #{ex.message}."
  else
    projects[project_reference]["lead_org"] = project_details_json["projectOverview"]["projectComposition"]["leadResearchOrganisation"]["name"]
    projects[project_reference]["lead_org_dept"] = project_details_json["projectOverview"]["projectComposition"]["leadResearchOrganisation"]["department"]
    full_address = project_details_json["projectOverview"]["projectComposition"]["leadResearchOrganisation"]["address"]
    projects[project_reference]["lead_org_address"] = full_address.map{|k,v| "#{v}" }.join(', ')
    projects[project_reference]["lead_org_postcode"] = project_details_json["projectOverview"]["projectComposition"]["leadResearchOrganisation"]["address"]["postCode"]
    projects[project_reference]["lead_org_region"] = project_details_json["projectOverview"]["projectComposition"]["leadResearchOrganisation"]["address"]["region"]
    projects[project_reference]["funder"] = project_details_json["projectOverview"]["projectComposition"]["project"]["fund"]["funder"]["name"]
    projects[project_reference]["start"] = project_details_json["projectOverview"]["projectComposition"]["project"]["fund"]["start"]
    projects[project_reference]["end"] = project_details_json["projectOverview"]["projectComposition"]["project"]["fund"]["end"]
    projects[project_reference]["award_in_pounds"] = project_details_json["projectOverview"]["projectComposition"]["project"]["fund"]["valuePounds"]
    projects[project_reference]["gtr_url"] = project_details_json["projectOverview"]["projectComposition"]["project"]["url"]

    # Get principal investigator's details
    principal_investigator = project_details_json["projectOverview"]["projectComposition"]["personRole"].detect { |h| h["role"].detect { |h1| h1["name"] == "TRAINING_GRANT_HOLDER" or h1["name"] == "PRINCIPAL_INVESTIGATOR" } }
    unless principal_investigator.nil?
      projects[project_reference]["grant_holder_firstname"] = principal_investigator["firstName"]
      projects[project_reference]["grant_holder_othernames"] = principal_investigator["otherNames"]
      projects[project_reference]["grant_holder_surname"] = principal_investigator["surname"]
    end

    puts "Extracted project details for project #{project_reference}: "
    projects[project_reference].each do |key, value|
      puts "#{key.to_s}: #{value}"
    end
  end
end

# Export the CDT/DTP project results into a CSV spreadsheet saved in the data folder.
date = Time.now.strftime("%Y-%m-%d")
csv_file_path = "CDT_DTP_projects_#{date}.csv"
FileUtils.touch(csv_file_path) unless File.exist?(csv_file_path)

# CSV table header with info about the resulting CDT/DTP projects to be exported into a CSV file.
csv_headers = ["title",
               "funder",
               "project_reference",
               "grant_category",
               "start",
               "end",
               "award_in_pounds",
               "lead_org",
               "lead_org_dept",
               "lead_org_address",
               "lead_org_postcode",
               "lead_org_region",
               "grant_holder_firstname",
               "grant_holder_othernames",
               "grant_holder_surname",
               "gtr_url"]

begin
  CSV.open(csv_file_path, 'w',
           :write_headers => true,
           :headers => csv_headers #< column headers
  ) do |csv|
    projects.each do |project_reference, project_details|
      csv << [project_details["title"],
              project_details["funder"],
              project_reference,
              project_details["grant_category"],
              project_details["start"],
              project_details["end"],
              project_details["award_in_pounds"],
              project_details["lead_org"],
              project_details["lead_org_dept"],
              project_details["lead_org_address"],
              project_details["lead_org_postcode"],
              project_details["lead_org_region"],
              project_details["grant_holder_firstname"],
              project_details["grant_holder_othernames"],
              project_details["grant_holder_surname"],
              project_details["gtr_url"]]
    end
    puts "\n" + "#" * 80 +"\n\n"
    puts "Finished writing the CDT/DTP project data into #{csv_file_path}."
  end
rescue Exception => ex
  puts "\n" + "#" * 80 +"\n\n"
  puts "Failed to get export the CDT/DTP project data into #{csv_file_path}. An error of type #{ex.class} occurred, the reason being: #{ex.message}."
end

