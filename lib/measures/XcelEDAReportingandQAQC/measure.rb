# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

# start the measure
class XcelEDAReportingandQAQC < OpenStudio::Measure::ReportingMeasure

  # require all .rb files in resources folder
  Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }
  # incude module
  include OsLib_CreateResults

  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'XcelEDAReportingandQAQC'
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # Request the day type to use in the peak demand window checks.
    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Day Type Index,timestep;').get

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # make the runner a class variable
    @runner = runner

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    runner.registerInitialCondition('Starting QAQC report generation')

    # get the last model and sql file
    @model = runner.lastOpenStudioModel
    if @model.is_initialized
      @model = @model.get
    else
      runner.registerError('Cannot find last model.')
      return false
    end

    @sql = runner.lastEnergyPlusSqlFile
    if @sql.is_initialized
      @sql = @sql.get
    else
      runner.registerError('Cannot find last sql file.')
      return false
    end

    # define the time-of-use periods for electricity consumption
    electricity_consumption_tou_periods = [
      {
        'tou_name' => 'system_peak',
        'tou_id' => 1,
        'skip_weekends' => true,
        'skip_holidays' => true,
        'start_mo' => 'June',
        'start_day' => 1,
        'start_hr' => 14,
        'end_mo' => 'September',
        'end_day' => 30,
        'end_hr' => 18
      },
      {
        'tou_name' => 'peak',
        'tou_id' => 2,
        'skip_weekends' => true,
        'skip_holidays' => true,
        'start_mo' => 'January',
        'start_day' => 1,
        'start_hr' => 7,
        'end_mo' => 'December',
        'end_day' => 31,
        'end_hr' => 22
      },
      {
        'tou_name' => 'low_value_spring',
        'tou_id' => 4,
        'skip_weekends' => false,
        'skip_holidays' => false,
        'start_mo' => 'February',
        'start_day' => 1,
        'start_hr' => 0,
        'end_mo' => 'April',
        'end_day' => 30,
        'end_hr' => 6
      },
      {
        'tou_name' => 'low_value_fall',
        'tou_id' => 4,
        'skip_weekends' => false,
        'skip_holidays' => false,
        'start_mo' => 'November',
        'start_day' => 1,
        'start_hr' => 0,
        'end_mo' => 'November',
        'end_day' => 30,
        'end_hr' => 6
      },
      {
        'tou_name' => 'average',
        'tou_id' => 3,
        'skip_weekends' => false,
        'skip_holidays' => false,
        'start_mo' => 'January',
        'start_day' => 1,
        'start_hr' => 0,
        'end_mo' => 'December',
        'end_day' => 31,
        'end_hr' => 24
      }
    ]

    # vector to store the results and checks
    report_elems = OpenStudio::AttributeVector.new
    report_elems << create_results(skip_weekends = true,
                                   skip_holidays = true,
                                   start_mo = 'June',
                                   start_day = 1,
                                   start_hr = 14,
                                   end_mo = 'September',
                                   end_day = 30,
                                   end_hr = 18,
                                   electricity_consumption_tou_periods)

    # create an attribute vector to hold the checks
    check_elems = OpenStudio::AttributeVector.new

    # unmet hours check
    check_elems << unmet_hrs_check

    # energy use for cooling and heating as percentage of total energy check
    check_elems << enduse_pcts_check

    # peak heating and cooling months check
    check_elems << peak_heat_cool_mo_check

    # EUI check
    check_elems << eui_check

    # Register Values for all of the checks
    check_elems.each do |check|
      check_uid = OpenStudio.removeBraces(OpenStudio.createUUID)
      # loop through attributes (name,category,description,then optionally one or more flag attributes)
      check.valueAsAttributeVector.each_with_index do |value, index|
        if index == 0 # name
          runner.registerValue("qaqc_name_#{check_uid}", value.valueAsString)
        elsif index == 1 # category
          runner.registerValue("qaqc_cat_#{check_uid}", value.valueAsString)
        elsif index == 2 # description
          runner.registerValue("qaqc_desc_#{check_uid}", value.valueAsString)
        else # flag
          flag_uid = OpenStudio.removeBraces(OpenStudio.createUUID)
          runner.registerValue("qaqc_flag_#{check_uid}_#{flag_uid}", value.valueAsString)
        end
      end
    end

    # end checks
    report_elems << OpenStudio::Attribute.new('checks', check_elems)

    # create an extra layer of report.  the first level gets thrown away.
    top_level_elems = OpenStudio::AttributeVector.new
    top_level_elems << OpenStudio::Attribute.new('report', report_elems)

    # create the report
    result = OpenStudio::Attribute.new('summary_report', top_level_elems)
    result.saveToXml(OpenStudio::Path.new('report.xml'))

    # closing the sql file
    @sql.close

    # reporting final condition
    runner.registerFinalCondition('Finished generating report.xml.')

    return true
  end
end

# this allows the measure to be use by the application
XcelEDAReportingandQAQC.new.registerWithApplication
