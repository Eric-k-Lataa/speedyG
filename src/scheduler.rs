// src/scheduler.rs
use crate::state_machine::{new_job, Job, JobEvent};
use std::collections::VecDeque;
use serde::{Serialize, Deserialize};

/// Administrador de la cola de tareas y envio (?) hacia el Executor
#[derive(Serialize, Deserialize)]
pub struct Scheduler {
    next_id: u32,
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

    /// Encola un nuevo comando usando la máquina de estados
    pub fn add_job(&mut self, program: String, args: Vec<String>) -> &Job {
        let job = new_job(self.next_id, program, args, true);
        self.next_id += 1;
        self.queue.push_back(job);
        self.queue.back().unwrap()
    }

    /// Busca un Job por ID tanto en la cola activa como en el historial
    pub fn get_job(&self, id: u32) -> Option<&Job> {
        self.queue
            .iter()
            .chain(self.history.iter())
            .find(|j| j.get_id() == id)
    }

    /// Cancela un Job si aún está en la cola o ejecución
    pub fn cancel_job(&mut self, id: u32) -> bool {
        if let Some(pos) = self.queue.iter().position(|j| j.get_id() == id) {
            let mut job = self.queue.remove(pos).unwrap();
            job.transition(JobEvent::Cancel);
            self.history.push(job);
            true
        } else {
            false
        }
    }

    /// Marca un proceso como running (para cuando se llaman asincronos mas que nada)
    pub fn start_job(&mut self, id: u32) -> bool {
        if let Some(job) = self.queue.iter_mut().find(|j| j.get_id() == id) {
            job.transition(JobEvent::CapacityAvailable);
            true
        } else {
            false
        }
    }

    /// Completa la ejecución de un trabajo y actualiza la FSM
    pub fn complete_job(&mut self, id: u32, exit_code: i32) -> bool {
        if let Some(pos) = self.queue.iter().position(|j| j.get_id() == id) {
            let mut job = self.queue.remove(pos).unwrap();
            // Solo enviamos Completed, el Job ya pasó a Running mediante start_job
            job.transition(JobEvent::Completed(exit_code));
            self.history.push(job);
            true
        } else {
            false
        }
    }

    /// Retorna una lista de referencias con las tareas actualmente en cola
    pub fn pending_jobs(&self) -> Vec<&Job> {
        self.queue.iter().collect()
    }

    /// Retorna una lista de referencias con el historial de tareas finalizadas
    pub fn history_jobs(&self) -> Vec<&Job> {
        self.history.iter().collect()
    }
}
