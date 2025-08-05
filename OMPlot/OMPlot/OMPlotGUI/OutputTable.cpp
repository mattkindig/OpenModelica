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
#include "util/read_csv.h"
#include "util/read_matlab4.h"

namespace OMPlot {


OutputTable::OutputTable(QString filename, const QStringList variables, QWidget* parent, bool interactive) :
	QTableView(parent), mInteractive(interactive)
{
	mModel = new TableModel(filename, variables);
	setModel(mModel);
    mModel->initializeModel(filename, variables);
    // set table properties
    setObjectName("resultTable");
    setSortingEnabled(false);
}

OutputTable::~OutputTable()
{
}

TableModel::TableModel(QString filename, const QStringList variables, QObject* parent) :
	QAbstractTableModel(parent)
{
	initializeModel(filename, variables);
}

TableModel::~TableModel() {
    clearModel();
}

bool TableModel::initializeModel(QString filename, const QStringList variables)
{
    mDefined = false;
    if (filename.isEmpty()) {
        // pass
    } else if (QFile::exists(filename)) { 
        mFile.setFileName(filename);
        mVariableList = retrieveVariableData(variables);
        mDefined = true;
    } else {
        throw NoFileException(QString("File not found : ").append(filename).toStdString().c_str());
    }
    return mDefined;
}

QStringList TableModel::retrieveVariableData(const QStringList variableList)
{
    QStringList variablesRetrieved, variablesRemaining;
    foreach (QString variableName, variableList) {
        if (mVariableData.contains(variableName) && !mVariableData.value(variableName).isEmpty()) {
            variablesRetrieved.append(variableName);
        } else {
            variablesRemaining.append(variableName);
        }
    }
    if (variablesRemaining.isEmpty()) {
        // all variables have already been retrieved from the file
        return variablesRetrieved;
    }
    //PLT file
    if (mFile.fileName().endsWith("plt"))
    {
        // open the file
        mFile.open(QIODevice::ReadOnly);
        mpTextStream = new QTextStream(&mFile);
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
        mFile.close();
        return variablesRetrieved;
    }
    //CSV file
    else if (mFile.fileName().endsWith("csv"))
    {
        /* open the file */
        struct csv_data* csvReader;
        csvReader = read_csv(mFile.fileName().toStdString().c_str());
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
        if (0 != (msg = omc_new_matlab4_reader(mFile.fileName().toStdString().c_str(), &reader))) {
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
    mTimeVariable = "";
    mTimeData.clear();
    mVariableList.clear();
    mVariableData.clear();
    mFile.remove();
    mDefined = false;
}

void TableModel::setTimeVariable(QString timeVariable)
{
	mTimeVariable = timeVariable;
}

int TableModel::rowCount(const QModelIndex& parent) const 
{
    return isDefined() ? mTimeData.size() : 100;
}

int TableModel::columnCount(const QModelIndex &parent) const
{
    return isDefined() ? mVariableList.size() : 6;
}

QVariant TableModel::data(const QModelIndex& index, int role) const
{
	int row = index.row();
	int column = index.column();
	QVariant invalid; 
	if (index.isValid() && (row < rowCount()) && (column < columnCount()) && isDefined()) {
		if (role == Qt::DisplayRole) {
            QString variableName = mVariableList[column];
            QVector<double> data = mVariableData.value(variableName, QVector<double>() );
            if (data.isEmpty()) { 
                return invalid; 
            }
            double value = data.size() == 1 ? data[0] : data[row];
			return QString::number(value);
		}
		return invalid;
	}
	return invalid;
}


QVariant TableModel::headerData(int section, Qt::Orientation orientation, int role) const {
	if ( (role != Qt::DisplayRole) || (! isDefined())) {
		return QVariant();
	}
	if (orientation == Qt::Vertical) {
        double value = mTimeData[section];
        return QString::number(value);
	}
	else {  // orientation == Qt::Vertical
        QString variableName = mVariableList[section];
		return variableName;
	}
	return QVariant();    // invalid
}

}  // namespace OMPlot