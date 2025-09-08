/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

#include "OutputTable.h"
#include "PlotWindow.h"    // for exceptions
#include "util/read_csv.h"
#include "util/read_matlab4.h"

namespace OMPlot {

const int defaultTimeCount = 100, defaultVariableCount = 6;

TableWindow::TableWindow(QString filename, const QStringList &variables, QWidget* parent, bool interactive) 
    : QMainWindow(parent)  
{
    // FOR DEBUGGING -- change initializeModel call back to 'filename' and 'variables'
    QString Filename = "C:\\Users\\mkindig.CYTEKBIO\\OneDrive - Cytek Biosciences Inc\\Documents\\OpenModelica\\LotkaVolterra\\LotkaVolterra_res.mat";
    QStringList Variables; Variables << "pred_pop" << "prey_pop" << "alpha";

    // create child objects
    mTable = new OutputTable(this);
    mModel = new TableModel(this);
    mTable->setModel(mModel);
    mModel->initializeModel(Filename, Variables);
    // set some UI properties
    QPalette p(palette());
    p.setColor(QPalette::Window, Qt::white);
    setAutoFillBackground(true);
    setPalette(p);
    setObjectName("resultTable");
    setInteractive(interactive);
    setCentralWidget(mTable);
}

TableWindow::~TableWindow() 
{
    delete mModel;
    delete mTable;
}

void TableWindow::clear()
{
    getModel()->clearModel();
    getTable()->update();
}


OutputTable::OutputTable(QWidget* parent) :
	QTableView(parent)
{
    setSortingEnabled(false);
}

OutputTable::~OutputTable()
{
}

bool OutputTable::transpose()
{
    bool result = getModel()->transposeModel();
    update();
    return result;
}


TableModel::TableModel(QObject* parent) :
	QAbstractTableModel(parent)
{
    mTimeAcrossColumns = true;
}

TableModel::~TableModel() {
    clearModel();
}

bool TableModel::initializeModel(QString filename, const QStringList &variables)
{
    clearModel(); // initialize variables
    updateVariableData(filename, variables);
    return isDefined();
}

bool TableModel::isDefined() const {
    return (!getAbsoluteFilepath().isEmpty()) && mFile.isFile();
}

/* Update specified variables with the data in the specified file. 
   Returns the list of updated variables, filtering out variables that are not in file
*/
QStringList TableModel::updateVariableData(QString filename, const QStringList &variables)
{
    // first get new filename and modified time
    QString currentFile = getAbsoluteFilepath();
    if (filename.isEmpty()) {
        if (currentFile.isEmpty()) {
            return QStringList();  // invalid model
        }
        // otherwise, use existing mFile
    } else if (!QFile::exists(filename)) {
        throw NoFileException(QString("File not found : ").append(filename).toStdString().c_str());
        return QStringList();
    } else {  // file exists, so use it
        mFile = QFileInfo(filename);
    }
    QDateTime newModTime = mFile.lastModified();
    // if filename is same and it hasn't been updated since last read, use cache
    bool useCachedData = (currentFile.compare(mFile.absoluteFilePath()) == 0) && newModTime.isValid() && (newModTime == mFileLastModified);
    if (! useCachedData) {
        mVariableData.clear();   // clear cache
        mFileLastModified = newModTime;
    }
    // Variables which are already in mVariableList are kept in same order; new variables are appended to the end in the order they appear in 'variables'.
    // This ensures that the existing display order is not changed when adding additional variables.
    QStringList variableList = variables.isEmpty() ? mVariableList : variables;
    QStringList newVariableList;
    foreach(QString variableName, mVariableList) {
        int index = variableList.indexOf(variableName);
        if (index >= 0) {
            newVariableList.append(variableName);
            variableList.removeAt(index);
        }
    }
    newVariableList.append(variableList);  
    // newVariableList may include variables that aren't in the cache or file. Filter those out
    QStringList variablesInCache, variablesInFile;
    foreach(QString variableName, newVariableList) {
        if (useCachedData && mVariableData.contains(variableName) && (!mVariableData.value(variableName, QVector<double>()).isEmpty())) {
            variablesInCache.append(variableName);
        } else {
            variablesInFile.append(variableName);
        }
    }
    variablesInFile = retrieveVariableDataFromFile(variablesInFile);
    mVariableList.clear();
    foreach(QString variableName, newVariableList) {
        if (variablesInCache.contains(variableName) || variablesInFile.contains(variableName)) {
            mVariableList.append(variableName);
        }
    }
    return mVariableList;
}

QStringList TableModel::retrieveVariableDataFromFile(const QStringList &variableList)
{
    if (variableList.isEmpty()) {
        return QStringList(); 
    }
    QStringList variablesRetrieved;
    QStringList variablesRemaining = variableList;
    //PLT file
    if (mFile.fileName().endsWith("plt"))
    {
        // open the file
        QFile fileReader(getAbsoluteFilepath());
        fileReader.open(QIODevice::ReadOnly);
        mpTextStream = new QTextStream(&fileReader);
        QString currentLine("");
        // read the interval size from the file
        int intervalSize = 0;
        while (!mpTextStream->atEnd())
        {
            currentLine = mpTextStream->readLine();
            if (currentLine.startsWith("#IntervalSize"))
            {
                intervalSize = static_cast<QString>(currentLine.split("=").last()).toInt();
                break;
            }
        }
        mTimeVariable = "time";
        mTimeData.clear();
        bool assignTime = true;
        // Read variable values from file
        while (!mpTextStream->atEnd())
        {
            currentLine = mpTextStream->readLine();
            if (currentLine.contains("DataSet:"))
            {
                QString currentVariable = currentLine.remove("DataSet: ").trimmed();
                int index = variablesRemaining.indexOf(currentVariable);
                if (index >= 0)
                {
                    // read the variable values now
                    QVector<double> ydata;
                    currentLine = mpTextStream->readLine();
                    for (int j = 0; j < intervalSize; j++)
                    {
                        QStringList values = currentLine.split(",");
                        if (assignTime) {
                            mTimeData.append(QString(values[0]).toDouble());
                        }
                        ydata.append(QString(values[1]).toDouble());
                        currentLine = mpTextStream->readLine();
                    }
                    mVariableData.insert(currentVariable, ydata);
                    variablesRetrieved.append(currentVariable);
                    variablesRemaining.removeAt(index);
                    assignTime = false;
                }
                else if (currentVariable.compare("time", Qt::CaseInsensitive) == 0) {
                    mTimeVariable = currentVariable;
                }
                // if no additional variables to read, no need to read further
                if (variablesRemaining.isEmpty()) {
                    break;
                }
            }
        }
        // if some variables of the specified variables were not found, throw error
        if (!variablesRemaining.isEmpty()) {
            throw NoVariableException(QString("Variables not found: ")
                .append(variablesRemaining.join(",")).toStdString().c_str());
        }
        // close the file
        fileReader.close();
        return variablesRetrieved;
    }
    //CSV file
    else if (mFile.fileName().endsWith("csv"))
    {
        /* open the file */
        struct csv_data* csvReader;
        csvReader = read_csv(getAbsoluteFilepath().toStdString().c_str());
        if (csvReader == NULL)
            throw PlotException(tr("Failed to open simulation result file %1").arg(mFile.fileName()));

        //Read in timevector
        mTimeVariable = "time";
        double* timeVals = read_csv_dataset(csvReader, mTimeVariable.toStdString().c_str());
        if (timeVals == NULL)
        {
            mTimeVariable = "lambda";
            timeVals = read_csv_dataset(csvReader, mTimeVariable.toStdString().c_str());
            if (timeVals == NULL)
            {
                mTimeVariable = "";
                omc_free_csv_reader(csvReader);
                throw NoVariableException(tr("Variable doesnt exist: %1").arg("time or lambda").toStdString().c_str());
            }
        }
        mTimeData = QVector<double>(timeVals, timeVals + csvReader->numsteps);
        // read in specified variables
        for (int i = 0; i < csvReader->numvars; i++)
        {
            char *variable = csvReader->variables[i];
            QString Variable(variable);
            int index = variablesRemaining.indexOf(Variable);
            if (index >= 0)
            {
                double* vals = read_csv_dataset(csvReader, variable);
                if (vals == NULL)
                {
                    omc_free_csv_reader(csvReader);
                    throw NoVariableException(tr("Variable doesn't exist in file: %1").arg(Variable).toStdString().c_str());
                }
                QVector<double> ydata(vals, vals + csvReader->numsteps);
                mVariableData.insert(Variable, ydata);
                variablesRetrieved.append(Variable);
                variablesRemaining.removeAt(index);
            }
        }
        // if some variables of the specified variables were not found, throw error
        if (!variablesRemaining.isEmpty()) {
            throw NoVariableException(QString("Variables not found: ")
                .append(variablesRemaining.join(",")).toStdString().c_str());
        }
        // close the file
        omc_free_csv_reader(csvReader);
        return variablesRetrieved;
    }
    //MAT file
    else if (mFile.fileName().endsWith("mat"))
    {
        ModelicaMatReader reader;
        ModelicaMatVariable_t* var;
        const char* msg = "";
        //Read in mat file
        if (0 != (msg = omc_new_matlab4_reader(getAbsoluteFilepath().toStdString().c_str(), &reader))) {
            throw PlotException(msg);
        }
        //Read in time vector
        if (reader.nvar < 1) {
            omc_free_matlab4_reader(&reader);
            throw NoVariableException("Variable doesnt exist: time");
        }
        var = omc_matlab4_find_var(&reader, "time");
        if (!var) {
            omc_free_matlab4_reader(&reader);
            throw NoVariableException(QString("Corrupt file. nvar %1").arg(reader.nvar).toStdString().c_str());
        }
        mTimeVariable = QString(var->name);
        double* timeVals = omc_matlab4_read_vals(&reader, var->index);
        mTimeData = QVector<double>(timeVals, timeVals + reader.nrows);
        // loop through all variables and read requested data
        for (uint32_t i = 0; i < reader.nall; i++) {
            char* variable = reader.allInfo[i].name;
            QString Variable(variable);
            int index = variablesRemaining.indexOf(Variable);
            if (index >= 0) 
            {
                // read the variable values
                var = omc_matlab4_find_var(&reader, variable);
                if (!var) {
                    omc_free_matlab4_reader(&reader);
                    throw NoVariableException(QString("Variable doesn't exist : ").append(Variable).toStdString().c_str());
                }
                QVector<double> ydata;
                if (!var->isParam) {    // not a parameter, save as full time history
                    double* vals = omc_matlab4_read_vals(&reader, var->index);
                    if (!vals) {
                        omc_free_matlab4_reader(&reader);
                        throw NoVariableException(QString("Corrupt file. nvar %1").arg(reader.nvar).toStdString().c_str());
                    }
                    ydata = QVector<double>(vals, vals + reader.nrows);
                }
                else { // parameter, save as single element array
                    double val;
                    if (omc_matlab4_val(&val, &reader, var, 0.0)) {
                        omc_free_matlab4_reader(&reader);
                        throw NoVariableException(QString("Parameter doesn't have a value : ").append(Variable).toStdString().c_str());
                    }
                    ydata.append(val);
                }
                mVariableData.insert(Variable, ydata);
                variablesRetrieved.append(Variable);
                variablesRemaining.removeAt(index);
            }
        }
        // if some variables of the specified variables were not found, throw error
        if (!variablesRemaining.isEmpty()) {
            throw NoVariableException(QString("Variables not found: ")
                .append(variablesRemaining.join(",")).toStdString().c_str());
        }
        // close the file
        omc_free_matlab4_reader(&reader);
        return variablesRetrieved;
    }
    else {   // invalid file type
        return QStringList();
    }
}

void TableModel::clearModel()
{
    beginResetModel();
    mTimeVariable = "";
    mTimeData.clear();
    mVariableList.clear();
    mVariableData.clear();
    mFile = QFileInfo();   // invalid
    mFileLastModified = QDateTime();  // invalid
    endResetModel();
}

void TableModel::setTimeVariable(QString timeVariable)
{
	mTimeVariable = timeVariable;
}

double TableModel::getVariableData(QString variableName, int timeIndex, bool& valid) const 
{
    QVector<double> varData;
    if (variableName.compare(getTimeVariable()) == 0) {
        varData = mTimeData;
    } else {
        varData = mVariableData.value(variableName, QVector<double>());
    }
    qsizetype n = varData.size();      // n==0 if data for variable not found
    if ( (n == 0) || (timeIndex < 0)) {     
        valid = false;
        return 0.0;
    } else if (n == 1) {   // parameter
        valid = true;
        return varData[0];
    } else if (timeIndex >= n) {   
        valid = false;
        return 0.0;
    }  else {    // continuous data
        valid = true;
        return varData[timeIndex];
    }
}

int TableModel::rowCount(const QModelIndex &parent) const 
{
    if (isDefined()) {
        return mTimeAcrossColumns ? mVariableList.size() : mTimeData.size();
    }
    return mTimeAcrossColumns ? defaultVariableCount : defaultTimeCount;
}

int TableModel::columnCount(const QModelIndex &parent) const
{
    if (isDefined()) {
        return mTimeAcrossColumns ? mTimeData.size() : mVariableList.size();
    }
    return mTimeAcrossColumns ? defaultTimeCount : defaultVariableCount;
}

QVariant TableModel::data(const QModelIndex& index, int role) const
{
	int row = index.row();
	int column = index.column();
	QVariant invalid; 
	if (index.isValid() && (row < rowCount()) && (column < columnCount()) && isDefined()) {
        int timeIndex = mTimeAcrossColumns ? column : row;
        int variableIndex = mTimeAcrossColumns ? row : column;
		if (role == Qt::DisplayRole) {
            bool valid = false;
            double value = getVariableData(mVariableList[variableIndex], timeIndex, valid);
            return valid ? QString::number(value) : invalid;
		}
		return invalid;
	}
	return invalid;
}


QVariant TableModel::headerData(int section, Qt::Orientation orientation, int role) const {
    QVariant invalid;
	if ( (role != Qt::DisplayRole) || (! isDefined())) {
		return invalid;
	}
    if (mTimeAcrossColumns) {
        if (orientation == Qt::Horizontal) {
            bool valid = false;
            double value = getVariableData(getTimeVariable(), section, valid);
            return valid ? QString::number(value) : invalid;
        }
        else {  // orientation == Qt::Vertical
            QString variableName = mVariableList[section];
            return variableName;
        }
    } else {
        if (orientation == Qt::Vertical) {
            bool valid = false;
            double value = getVariableData(getTimeVariable(), section, valid);
            return valid ? QString::number(value) : invalid;
        }
        else {  // orientation == Qt::Horizontal
            QString variableName = mVariableList[section];
            return variableName;
        }
    }
	return invalid;    
}

bool TableModel::transposeModel() {
    beginResetModel();
    mTimeAcrossColumns = !mTimeAcrossColumns;
    endResetModel();
    return mTimeAcrossColumns;
}



}  // namespace OMPlot