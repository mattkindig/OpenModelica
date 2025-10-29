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

#ifndef OUTPUTTABLE_H
#define OUTPUTTABLE_H

#include "OMPlot.h"
#include "PlotWindowContainer.h"  // for ResultWindow


#include <QAbstractTableModel>
#include <QTableView>
#include <QFileInfo>
#include <QDateTime>

namespace OMPlot 
{

class TableWindow;
class OutputTable;
class TableModel;

struct TableUnit {
	double scale;
	double offset;
	QString unit;
	QString displayUnit;
	TableUnit(QString unit = "", QString displayUnit = "", double scale = 1.0, double offset = 0.0) {
		this->scale = scale;
		this->offset = offset;
		this->unit = unit;
		this->displayUnit = displayUnit.isEmpty() ? this->unit : displayUnit;
	}
};

typedef QHash<QString, QVector<double>> VarData;

class OutputTable : public QTableView
{
	Q_OBJECT
public:
	OutputTable(TableWindow* parent = nullptr);
	~OutputTable();
	TableModel* getModel() const { return mModel; }
	TableWindow* getTableWindow() const { return mWindow; }
	bool transpose();

private:
	TableModel* mModel;  // associated model
	TableWindow* mWindow;  // associated parent window
};

class TableModel : public QAbstractTableModel
{
	Q_OBJECT
public:
	TableModel(QObject *parent = nullptr, OutputTable* table = nullptr);
	~TableModel();
	bool initializeModel(QString filename, const QStringList &variables = QStringList());
	void setTable(OutputTable* table) { mpTable = table; }
	OutputTable* getTable() const { return mpTable; }
	
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;
	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;

	bool isDefined() const;
	QString getFilename() const { return isDefined() ? mFile.fileName() : QString(""); }
	QString getAbsoluteFilePath() const { return isDefined() ? mFile.absoluteFilePath() : QString(""); }

	QStringList setVariables(const QStringList& variables, QString filename = "");
	bool addVariable(QString variableName, QString filename = "");
	QStringList addVariables(const QStringList& variableNames, QString filename = "");
	bool removeVariable(QString variableName);
	QStringList removeVariables(const QStringList& variableNames);
	QStringList updateVariables(); 

	void setTimeVariable(QString timeVariable);
	QString getTimeVariable() const { return mTimeVariable; }
	void setTimeUnit(QString timeUnit) { setUnit(mTimeVariable, timeUnit); }
	QString getTimeUnit() { return getUnit(mTimeVariable); }
	QString getTimeDisplayUnit() { return getDisplayUnit(mTimeVariable); }

	void setUnit(QString variableName, QString unit);
	QString getUnit(QString variableName) const;
	void setDisplayUnit(QString variableName, QString unit);
	QString getDisplayUnit(QString variableName) const;
	void setUnitScale(QString variableName, double scale, double offset);
	QString getUnitScale(QString variableName, double& scale, double& offset) const;

//	QStringList updateVariableData(QString filename = "", const QStringList &variables = QStringList(), bool errorIfFileMismatch = false);
	
	QVector<double> getTimes() const { return mTimeData;  }
	QStringList getVariables() const { return mVariableList; }
//	QStringList getVariableLabels() const;

	QVector<double> getVariableData(QString variableName) const { return mVariableData.value(variableName, QVector<double>()); }
	double getVariableValue(QString variableName, int timeIndex, bool& valid) const;

	void clearModel();
	bool transposeModel();
//	VarData updateVariables(QString filename, const QStringList &variables, const VarData &existingData, QString &timeVariable);
signals:
	void updateModel(QString filename, const QStringList& variables, QString timeVariable, const VarData& data);
private slots:	
	void updateModelSlot(QString filename, const QStringList& variables, QString timeVariable, const VarData& data);

private:
	QString getInputFilename(QString filename = "") const;
	QStringList updateVariableDataFromFile(QString filename, const QStringList &variableList, VarData &variableData, QString &timeVariable);
	bool cacheIsValid() const;
	QFileInfo mFile;
	QDateTime mFileLastModified;
	QString mTimeVariable;
	QVector<double> mTimeData;
	QStringList mVariableList;
	VarData mVariableData;
	OutputTable* mpTable;      
	QHash<QString, TableUnit> mUnitMap;
	bool mTimeAcrossColumns;
};

class TableWindow : public ResultWindow
{
	Q_OBJECT
public:
	TableWindow(QString filename = "", const QStringList& variables = QStringList(), QWidget* parent = 0, bool interactive = false);
	~TableWindow();
	OutputTable* getTable() const { return mTable; }
	TableModel* getModel() const { return mModel; }
	void setTitle(QString title) { mTitle = title; }
	QString getTitle() const { return mTitle; }
	void setInteractive(bool interactive) { mInteractive = interactive; }
	bool isInteractive() const { return mInteractive; }
	bool isPlotWindow() const { return false; }
	bool isTableWindow() const { return true; }
	void setSubWindow(QMdiSubWindow* pSubWindow) { mpSubWindow = pSubWindow; }
	QMdiSubWindow* getSubWindow() { return mpSubWindow; }
	void clear();
	void receiveMessage(QStringList arguments);

signals:
	void closingDown();

private:
	OutputTable* mTable;
	TableModel* mModel;
	QMdiSubWindow* mpSubWindow;
	QString mTitle;
	bool mInteractive;
};


class TableMultipleFileException : public PlotException
{
public:
	TableMultipleFileException(const char* fileName) : PlotException(fileName) {}
};


}  // namespace OMPlot
#endif   // OUTPUTTABLE_H