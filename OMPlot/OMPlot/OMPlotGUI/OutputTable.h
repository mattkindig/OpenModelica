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
	TableModel(QObject *parent = nullptr);
	~TableModel();
	bool initializeModel(QString filename, const QStringList &variables = QStringList());
	void setTable(OutputTable* table) { mpTable = table; }
	OutputTable* getTable() const { return mpTable; }
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;
	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
	QStringList updateVariableData(QString filename = "", const QStringList &variables = QStringList(), bool errorIfFileMismatch = false);
	void setTimeVariable(QString timeVariable);
	QString getTimeVariable() const { return mTimeVariable; }
	void setTimeUnit(QString timeUnit) { mTimeUnit = timeUnit; }
	QString getTimeUnit() { return mTimeUnit; }
	QVector<double> getTimes() const { return mTimeData;  }
	QStringList getVariables() const { return mVariableList; }
	QVector<double> getVariableVector(QString variableName) const { return mVariableData.value(variableName, QVector<double>()); }
	double getVariableData(QString variableName, int timeIndex, bool& valid) const;
	bool addVariable(QString variableName);
	bool removeVariable(QString variableName);
	bool isDefined() const;
	QString getFilename() const { return mFilename; }
	QString getAbsoluteFilepath() const { return isDefined() ? mFilename : QString(""); }
	void clearModel();
	bool transposeModel();

private:
	QStringList updateVariableDataFromFile(QString filename, const QStringList &variableList);
	QString mFilename;
	QDateTime mFileLastModified;
	QString mTimeVariable;
	QString mTimeUnit;
	QVector<double> mTimeData;
	QStringList mVariableList;
	QHash<QString, QVector<double>> mVariableData;
	QHash<QString, QString> mUnits, mDisplayUnits;
	OutputTable* mpTable;      
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