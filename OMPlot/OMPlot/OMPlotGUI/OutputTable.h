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

#ifndef OUTPUT_TABLE_H
#define OUTPUT_TABLE_H

#include "OMPlot.h"
#include "PlotWindowContainer.h"

#include <QAbstractTableModel>
#include <QTableView>

namespace OMPlot 
{

class TableModel;

class OutputTable : public QTableView
{
	Q_OBJECT
public:
	OutputTable(QString filename = "", const QStringList variables = QStringList(), QWidget* parent = nullptr, bool interactive = false);
	~OutputTable();
	TableModel* getModel() const { return mModel; }
	bool isInteractive() const { return mInteractive; }
private:
	TableModel* mModel;  // associated model
	bool mInteractive;
};

class TableModel : public QAbstractTableModel
{
	Q_OBJECT
public:
	TableModel(QString filename = "", const QStringList variables = QStringList(), QObject * parent = nullptr);
	~TableModel();
	bool initializeModel(QString filename, const QStringList variables = QStringList());
	int rowCount(const QModelIndex& parent = QModelIndex()) const override;
	int columnCount(const QModelIndex& parent = QModelIndex()) const override;
	QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
	QStringList retrieveVariableData(const QStringList variableList);
	void setTimeVariable(QString timeVariable);
	QString getTimeVariable() const { return mTimeVariable; }
	void setTimeUnit(QString timeUnit) { mTimeUnit = timeUnit; }
	QString getTimeUnit() { return mTimeUnit; }
	QVector<double> getTimes() const { return mTimeData;  }
	QStringList getVariables() const { return mVariableList; }
	QVector<double> getVariableData(QString variableName) const { return mVariableData.value(variableName, QVector<double>()); }
	bool isDefined() const { return mDefined; }
	QString getFilename() const { return mFile.fileName(); }
	void clearModel();

signals:
	void closingDown();

private:
	bool mDefined;
	QFile mFile;
	QString mTimeVariable;
	QString mTimeUnit;
	QVector<double> mTimeData;
	QStringList mVariableList;
	QHash<QString, QVector<double>> mVariableData;
	QTextStream* mpTextStream;
};

}  // namespace OMPlot
#endif   // OUTPUT_TABLE_H