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

#include <QDir>
#include <QSet>


namespace OMPlot {

static const int defaultTimeCount = 100, defaultVariableCount = 6;

static QStringList StringListFilter(const QStringList& listA, const QStringList& listB) {
    QStringList out;
    foreach(QString str, listA) {
        if (listB.contains(str)) {
            out.append(str);
        }
    }
    return out;
}

TableWindow::TableWindow(QString filename, const QStringList &variables, QWidget* parent, bool interactive) 
    : ResultWindow(parent)
{
    // create child objects
    mTable = new OutputTable(this);
    mModel = new TableModel(this, mTable);
    mTable->setModel(mModel);
    mModel->initializeModel(filename, variables);
    // set some UI properties
    QPalette p(palette());
    p.setColor(QPalette::Window, Qt::white);
    setAutoFillBackground(true);
    setPalette(p);
    setObjectName("tableWindow");
    setInteractive(interactive);
    setCentralWidget(mTable);
}

TableWindow::~TableWindow() 
{
}

void TableWindow::clear()
{
    getModel()->clearModel();
    getTable()->update();
}

void TableWindow::receiveMessage(QStringList arguments) 
{
    return;
}

OutputTable::OutputTable(TableWindow* parent) :
	QTableView(parent)
{
    mWindow = parent;
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


TableModel::TableModel(QObject* parent, OutputTable* table) :
	QAbstractTableModel(parent)
{
    mTimeAcrossColumns = true;
    setTable(table);
    connect(this, SIGNAL(updateModel(QString, const QStringList&, QString, const VarData&)),
        SLOT(updateModelSlot(QString, const QStringList&, QString, const VarData&)) );
    clearModel();
}

TableModel::~TableModel() {
    clearModel();
}

bool TableModel::initializeModel(QString filename, const QStringList &variables)
{
    clearModel();
    setVariables(variables, filename);
    return isDefined();
}

bool TableModel::isDefined() const {
    return mFile.exists() && (! mTimeData.isEmpty()) && (!mVariableList.isEmpty());
}

QString TableModel::getInputFilename(QString filename) const 
{
    const QString currentFile = getAbsoluteFilePath();
    QString newFile = QDir::cleanPath(filename.trimmed());
    const QString empty = "";
    if (newFile.isEmpty()) {
        if (currentFile.isEmpty()) {
            return empty;
        }
        return currentFile;
    } else if (!QFileInfo::exists(newFile)) {
        throw NoFileException(QString("File not found : ").append(newFile).toStdString().c_str());
        return empty;
    } else if ((!currentFile.isEmpty()) && (newFile.compare(currentFile) != 0)) {
        throw TableMultipleFileException(QString("Table can only contain variables from a single file. Existing file='%1', specified file='%2'").arg(currentFile).arg(newFile).toStdString().c_str());
        return empty;
    } else {
        QFileInfo fInfo(newFile);
        if (!fInfo.isReadable()) {
            throw NoFileException(QString("File not readable : ").append(newFile).toStdString().c_str());
            return empty;
        }
        return fInfo.absoluteFilePath();
    }
}

bool TableModel::cacheIsValid() const {
    if (!mFile.isFile()) {
        return false;
    }
    QDateTime newModTime = mFile.lastModified();
    return newModTime.isValid() && (newModTime == mFileLastModified);
}

QStringList TableModel::setVariables(const QStringList& variables, QString filename) 
{
    filename = getInputFilename(filename);
    QString timeVariable("");
    VarData variableData;
    if (cacheIsValid()) {
        variableData = VarData(mVariableData);
    }
    QStringList variableList = updateVariableDataFromFile(filename, variables, variableData, timeVariable);
    emit updateModel(filename, variableList, timeVariable, variableData);
    return variableList;
}

QStringList TableModel::updateVariables() {
    return setVariables(getVariables(), "");
}

/* Update specified variables with the data in the specified file. 
   Returns the list of updated variables, filtering out variables that are not in file
*/ 
QStringList TableModel::updateVariableDataFromFile(QString filename, const QStringList& variableList, VarData& variableData, QString& timeVariable)
{
    if (filename.isEmpty() || variableList.isEmpty()) {
        return QStringList(); 
    }
    QSet<QString> variablesDefined, variablesRemaining;
    foreach(QString variableName, variableList) {
        if (variableData.contains(variableName)) {
            variablesDefined.insert(variableName);
        } else {
            variablesRemaining.insert(variableName);
        }
    }
    if (variablesRemaining.isEmpty()) 
    {
        // no variables to extract from file, so just jump to end of function
    }
    //PLT file
    else if (filename.endsWith("plt"))
    {
        // open the file
        QFile fileReader(filename);
        fileReader.open(QIODevice::ReadOnly);
        QTextStream textStream(&fileReader);
        QString currentLine("");
        // read the interval size from the file
        int intervalSize = 0;
        while (!textStream.atEnd())
        {
            currentLine = textStream.readLine();
            if (currentLine.startsWith("#IntervalSize"))
            {
                intervalSize = static_cast<QString>(currentLine.split("=").last()).toInt();
                break;
            }
        }
        timeVariable = "time";
        QVector<double> timeData;
        bool assignTime = true;
        // Read variable values from file
        while (!textStream.atEnd())
        {
            currentLine = textStream.readLine();
            if (currentLine.contains("DataSet:"))
            {
                QString currentVariable = currentLine.remove("DataSet: ").trimmed();
                QSet<QString>::iterator it = variablesRemaining.find(currentVariable);
                if (it != variablesRemaining.end())
                {
                    // read the variable values now
                    QVector<double> ydata;
                    currentLine = textStream.readLine();
                    for (int j = 0; j < intervalSize; j++)
                    {
                        QStringList values = currentLine.split(",");
                        if (assignTime) {
                            timeData.append(QString(values[0]).toDouble());
                        }
                        ydata.append(QString(values[1]).toDouble());
                        currentLine = textStream.readLine();
                    }
                    variableData.insert(currentVariable, ydata);
                    variablesDefined.insert(currentVariable);
                    variablesRemaining.erase(it);
                    assignTime = false;
                }
                else if (currentVariable.compare("time", Qt::CaseInsensitive) == 0) {
                    timeVariable = currentVariable;
                }
                // if no additional variables to read, no need to read further
                if (variablesRemaining.isEmpty()) {
                    break;
                }
            }
        }
        variableData.insert(timeVariable, timeData);
        fileReader.close();
    }
    //CSV file
    else if (filename.endsWith("csv"))
    {
        /* open the file */
        struct csv_data* csvReader;
        csvReader = read_csv(filename.toStdString().c_str());
        if (csvReader == NULL)
            throw PlotException(tr("Failed to open simulation result file %1").arg(filename));
        //Read in timevector
        timeVariable = "time";
        double* timeVals = read_csv_dataset(csvReader, timeVariable.toStdString().c_str());
        if (timeVals == NULL)
        {
            timeVariable = "lambda";
            timeVals = read_csv_dataset(csvReader, timeVariable.toStdString().c_str());
            if (timeVals == NULL)
            {
                timeVariable = "";
                omc_free_csv_reader(csvReader);
                throw NoVariableException(tr("Variable doesnt exist: %1").arg("time or lambda").toStdString().c_str());
            }
        }
        QVector<double> timeData(timeVals, timeVals + csvReader->numsteps);
        variableData.insert(timeVariable, timeData);
        // read in specified variables
        for (int i = 0; i < csvReader->numvars; i++)
        {
            char *variable = csvReader->variables[i];
            QString Variable(variable);
            QSet<QString>::iterator it = variablesRemaining.find(Variable);
            if (it != variablesRemaining.end())
            {
                double* vals = read_csv_dataset(csvReader, variable);
                if (vals == NULL)
                {
                    omc_free_csv_reader(csvReader);
                    throw NoVariableException(tr("Variable doesn't exist in file: %1").arg(Variable).toStdString().c_str());
                }
                QVector<double> ydata(vals, vals + csvReader->numsteps);
                variableData.insert(Variable, ydata);
                variablesDefined.insert(Variable);
                variablesRemaining.erase(it);
            }
        }
        // close the file
        omc_free_csv_reader(csvReader);
    }
    //MAT file
    else if (filename.endsWith("mat"))
    {
        ModelicaMatReader reader;
        ModelicaMatVariable_t* var;
        const char* msg = "";
        //Read in mat file
        if (0 != (msg = omc_new_matlab4_reader(filename.toStdString().c_str(), &reader))) {
            throw PlotException(msg);
        }
        //Read in time vector
        if (reader.nvar < 1) {
            omc_free_matlab4_reader(&reader);
            throw NoVariableException("Variable doesn't exist: time");
        }
        var = omc_matlab4_find_var(&reader, "time");
        if (!var) {
            omc_free_matlab4_reader(&reader);
            throw NoVariableException(QString("Corrupt file. nvar %1").arg(reader.nvar).toStdString().c_str());
        }
        timeVariable = QString(var->name);
        double* timeVals = omc_matlab4_read_vals(&reader, var->index);
        QVector<double> timeData(timeVals, timeVals + reader.nrows);
        variableData.insert(timeVariable, timeData);
        // loop through all variables and read requested data
        for (uint32_t i = 0; i < reader.nall; i++) {
            char* variable = reader.allInfo[i].name;
            QString Variable(variable);
            QSet<QString>::iterator it = variablesRemaining.find(Variable);
            if (it != variablesRemaining.end()) 
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
                variableData.insert(Variable, ydata);
                variablesDefined.insert(Variable);
                variablesRemaining.erase(it);
            }
        }
        // close the file
        omc_free_matlab4_reader(&reader);
    }
    // if some variables of the specified variables were not found, throw error
    if (!variablesRemaining.isEmpty()) {
        QStringList missingVariables(variablesRemaining.begin(), variablesRemaining.end());
        throw NoVariableException(QString("Variables not found: ").append(missingVariables.join(",")).toStdString().c_str());
    }
    // return variables in originally passed-in order, removing variables that were not found
    QStringList extractedVariables;
    foreach(QString variableName, variableList) {
        if (variablesDefined.contains(variableName)) {
            extractedVariables.append(variableName);
        }
    }
    return extractedVariables;
}

bool TableModel::addVariable(QString variableName, QString filename)
{
    QStringList allVariables(mVariableList);
    allVariables.append(variableName);
    allVariables = setVariables(allVariables, filename);
    return allVariables.contains(variableName);
}

QStringList TableModel::addVariables(const QStringList& variableNames, QString filename) {
    QStringList allVariables(mVariableList);
    allVariables.append(variableNames);
    allVariables = setVariables(allVariables, filename);
    return StringListFilter(variableNames, allVariables);
}

bool TableModel::removeVariable(QString variableName)
{
    QStringList variableList(mVariableList);
    int index = variableList.indexOf(variableName);
    if (index >= 0) {
        variableList.removeAt(index);
        emit updateModel(getAbsoluteFilePath(), variableList, getTimeVariable(), mVariableData);
        return true;
    }
    return false;
}

QStringList TableModel::removeVariables(const QStringList& variableNames)
{
    QStringList removedVariables;
    QStringList variableList(mVariableList);
    foreach (QString variableName, variableNames) {
        int index = variableList.indexOf(variableName);
        if (index >= 0) {
            variableList.removeAt(index);
            removedVariables.append(variableName);
        }
    }
    emit updateModel(getAbsoluteFilePath(), variableList, getTimeVariable(), mVariableData);
    return removedVariables;
}

void TableModel::updateModelSlot(QString filename, const QStringList& variables, QString timeVariable, const VarData& data) 
{
    beginResetModel();
    if (filename.isEmpty() || variables.isEmpty()) {   // invalid file or empty variable list
        mFile = QFileInfo();
        mFileLastModified = QDateTime();
    } else {
        mFile = QFileInfo(filename);
        mFileLastModified = mFile.lastModified();
    }
    setTimeVariable(timeVariable);
    mVariableData = data;
    mTimeData = data.value(mTimeVariable);
    mVariableList = variables;
    endResetModel();
}

void TableModel::clearModel()
{
    VarData empty;
    emit updateModel("", QStringList(), "", empty);
}

void TableModel::setTimeVariable(QString timeVariable)
{
    if (!timeVariable.isEmpty()) {
        mTimeVariable = timeVariable;
    }
}

double TableModel::getVariableValue(QString variableName, int timeIndex, bool& valid) const 
{
    QVector<double> varData;
    if (variableName.compare(getTimeVariable()) == 0) {
        varData = mTimeData;
    } else {
        varData = mVariableData.value(variableName, QVector<double>());
    }
    int n = varData.size();      // n==0 if data for variable not found
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
            double value = getVariableValue(mVariableList[variableIndex], timeIndex, valid);
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
            double value = getVariableValue(getTimeVariable(), section, valid);
            return valid ? QString::number(value) : invalid;
        }
        else {  // orientation == Qt::Vertical
            QString variableName = mVariableList[section];
            return variableName;
        }
    } else {
        if (orientation == Qt::Vertical) {
            bool valid = false;
            double value = getVariableValue(getTimeVariable(), section, valid);
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
    mTimeAcrossColumns = ! mTimeAcrossColumns;
    endResetModel();
    return mTimeAcrossColumns;
}



}  // namespace OMPlot