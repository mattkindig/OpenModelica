/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Link�pings universitet, Department of Computer and Information Science,
 * SE-58183 Link�ping, Sweden.
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

namespace OMPlot {


OutputTable::OutputTable(const QStringList arguments, QWidget* parent) :
	QTableView(parent) 
{
	mModel = new TableModel(arguments);
	setModel(mModel);
}

OutputTable::~OutputTable()
{
}


TableModel::TableModel(QStringList arguments, QObject* parent) :
	QAbstractTableModel(parent)
{
	
}

void TableModel::setTimeVariable(QString timeVariable)
{
	mTimeVariable = timeVariable;
}

int TableModel::rowCount(const QModelIndex& parent) const 
{
	return mTimeData.size();
}

int TableModel::columnCount(const QModelIndex &parent) const
{
	return 1 + mVariableList.size();
}

QVariant TableModel::data(const QModelIndex& index, int role) const
{
	int row = index.row();
	int column = index.column();
	if ((!index.isValid()) || (row >= rowCount()) || (column >= columnCount())) {
		return QVariant();   // invalid
	}
	QString variable = mVariableList[row];
	QVector<double> data = mVariableData.value(variable);
	double value = data[column];
	return QVariant(value);
}

}  // namespace OMPlot


/*
QHash<QString, StringPair> units;

foreach (QString arg, args) {
   if (arg.isEmpty()) continue;
   QChar delimiter = arg[0];
   QStringList fields = arg.remove(0,1).split(delimiter, Qt::KeepEmptyParts);
   QString variableName, unit, displayUnit;
   switch (fields.size()) {
	case 0:   // empty string
	   continue;
	case 3:
	default:
	   displayUnit = fields[2].trimmed();
	   // fallthrough
	case 2:
	   unit = fields[1].trimmed();
	   // fallthrough
	case 1:
	   variableName = fields[0].trimmed();
	}
	variables.append(variableName);
	units.insert(variableName, qMakePair(unit,displayUnit));
}

*/