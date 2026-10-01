// src/scheduler.rs
use crate::executor::{ExecutionResult, Executor};
use std::collections::VecDeque;

/// Representa el estado en el que se encuentra una tarea dentro del scheduler
#[derive(Debug, Clone, PartialEq)]
pub enum JobStatus {
    Pending,
    Running,
    Completed(i32), // Almacena el exit_code final (ej. 0)
    Failed(i32),    // Almacena el exit_code de error
}

/// Estructura de un trabajo individual dentro de la cola
#[derive(Debug, Clone)]
pub struct Job {
    pub id: usize,
    pub command: String,
    pub status: JobStatus,
}

impl Job {
    pub fn new(id: usize, command: String) -> Self {
        Self {
            id,
            command,
            status: JobStatus::Pending,
        }
    }
}

/// Administrador de la cola de tareas y despacho hacia el Executor
pub struct Scheduler {
    next_id: usize,
    queue: VecDeque<Job>,
    history: Vec<Job>,
}

impl Scheduler {
    pub fn new() -> Self {
        Self {
            next_id: 1,
            queue: VecDeque::new(),
            history: Vec::new(),
        }
    }

    /// Encola un nuevo comando y devuelve el Job asignado
    pub fn add_job(&mut self, command: String) -> Job {
        let job = Job::new(self.next_id, command);
        self.next_id += 1;
        self.queue.push_back(job.clone());
        job
    }

    /// Despacha la siguiente tarea pendiente usando el Executor
    pub fn run_next(&mut self) -> Option<(Job, ExecutionResult)> {
        let mut job = self.queue.pop_front()?;
        job.status = JobStatus::Running;

        // Se ejecuta el subproceso usando el Executor que construiste
        let result = Executor::run(&job.command);

        // Actualizamos el estado final según el resultado
        if result.success {
            job.status = JobStatus::Completed(result.exit_code);
        } else {
            job.status = JobStatus::Failed(result.exit_code);
        }

        self.history.push(job.clone());
        Some((job, result))
    }

    /// Retorna una lista con las tareas actualmente en cola
    pub fn pending_jobs(&self) -> Vec<Job> {
        self.queue.iter().cloned().collect()
    }

    /// Retorna el historial de tareas finalizadas
    pub fn history_jobs(&self) -> Vec<Job> {
        self.history.clone()
    }
}

// Pruebas unitarias para validar el Scheduler
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_and_run_job() {
        let mut scheduler = Scheduler::new();
        let job = scheduler.add_job("echo 'test scheduler'".to_string());

        assert_eq!(job.id, 1);
        assert_eq!(scheduler.pending_jobs().len(), 1);

        let (completed_job, result) = scheduler.run_next().unwrap();
        assert_eq!(result.exit_code, 0);
        assert_eq!(completed_job.status, JobStatus::Completed(0));
        assert_eq!(scheduler.pending_jobs().len(), 0);
        assert_eq!(scheduler.history_jobs().len(), 1);
    }
}
