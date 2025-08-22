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

#include <QStandardItemModel>

namespace OMPlot {


OutputTable::OutputTable(const QStringList arguments, QWidget* parent) :
	QTableView(parent) 
{
	mModel = new TableModel(arguments);
	setModel(mModel);
	initializeTable(arguments);
}

OutputTable::~OutputTable()
{
}

void OutputTable::initializeTable(const QStringList arguments)
{
	// extract parameters that are part of model
	QStringList(tableArgs);
	tableArgs << arguments[1];
	mModel->initializeModel(tableArgs);
	for (int row = 0; row < mModel->rowCount(); row++) {
		for (int column = 0; column < mModel->columnCount(); column++) {
			QStandardItem* item = new QStandardItem(QString("iii"));
			mModel->setItem(row, column, item);
		}
	}
}


TableModel::TableModel(QStringList arguments, QObject* parent) :
	QAbstractTableModel(parent)
{
	if (false) { //(!arguments.isEmpty()) {
		initializeModel(arguments);
	}
}

void TableModel::initializeModel(QStringList arguments)
{
	QString file(arguments[1]);
	mFile.setFileName(file);
	if (!mFile.exists()) {
		throw NoFileException(QString("File not found : ").append(file).toStdString().c_str());
	}
}


void TableModel::setTimeVariable(QString timeVariable)
{
	mTimeVariable = timeVariable;
}

int TableModel::rowCount(const QModelIndex& parent) const 
{
	return 2; // mTimeData.size();
}

int TableModel::columnCount(const QModelIndex &parent) const
{
	return 3; // 1 + mVariableList.size();
}

QVariant TableModel::data(const QModelIndex& index, int role) const
{
	int row = index.row();
	int column = index.column();
	if ((!index.isValid()) || (row >= rowCount()) || (column >= columnCount())) {
		return QVariant();   // invalid
	}
	/*
	QString variable = mVariableList[row];
	QVector<double> data = mVariableData.value(variable);
	double value = data[column];
	return QVariant(value);
	*/

	// example code from https://doc.qt.io/qt-6/modelview.html
	if (role == Qt::DisplayRole) {
		return QString("Row%1, Column%2").arg(index.row() + 1).arg(index.column() + 1);
	}
}

}  // namespace OMPlot